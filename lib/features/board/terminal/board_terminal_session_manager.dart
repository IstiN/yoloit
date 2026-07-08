import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/terminal/data/remote_yoloit_terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

class BoardTerminalSessionManager extends ChangeNotifier {
  BoardTerminalSessionManager._();

  static final instance = BoardTerminalSessionManager._();

  final _backendService = TerminalBackendService.instance;
  final Map<String, AgentSession> _sessions = {};
  final Map<String, StreamSubscription<String>> _outputSubs = {};
  final Map<String, List<String>> _envGroupIdsBySession = {};

  // Batched output buffer per session to avoid flooding the xterm
  // [notifyListeners] bridge on every PTY chunk. When a runner dumps
  // thousands of lines per second, each [Terminal.write] triggers a full
  // UI rebuild; batching reduces that to ~20 rebuilds/sec.
  final Map<String, StringBuffer> _batchedOutput = {};
  final Map<String, Timer> _batchFlushTimers = {};
  static const _batchFlushIntervalMs = 50;
  static const _batchMaxBytes = 16384;

  AgentSession? sessionFor(String id) => _sessions[id];
  bool isLive(String id) => _sessions.containsKey(id);

  @visibleForTesting
  void setSessionForTesting(String sessionId, AgentSession session) {
    _sessions[sessionId] = session;
    notifyListeners();
  }

  @visibleForTesting
  void clearSessionsForTesting() {
    _sessions.clear();
    _envGroupIdsBySession.clear();
  }

  Future<AgentSession> ensureSession(
    BoardTerminalConfig config, {
    RemoteBoardInfo? remoteInfo,
    ResourceSessionMetadata? metadata,
  }) async {
    final existing = _sessions[config.sessionId];
    if (existing != null) return existing;
    return _spawn(
      sessionId: config.sessionId,
      sessionName: config.sessionName,
      workingDir: config.workingDir,
      envGroupIds: config.envGroupIds,
      remoteInfo: remoteInfo,
      metadata: metadata,
    );
  }

  Future<AgentSession> createSession({
    required String sessionName,
    required String workingDir,
    List<String> envGroupIds = const [],
    RemoteBoardInfo? remoteInfo,
    ResourceSessionMetadata? metadata,
  }) async {
    final sessionId = 'board_terminal_${DateTime.now().millisecondsSinceEpoch}';
    return _spawn(
      sessionId: sessionId,
      sessionName: sessionName,
      workingDir: workingDir,
      envGroupIds: envGroupIds,
      remoteInfo: remoteInfo,
      metadata: metadata,
    );
  }

  Future<void> renameSession(String sessionId, String sessionName) async {
    final current = _sessions[sessionId];
    if (current == null) return;
    _sessions[sessionId] = current.copyWith(
      customName: sessionName.trim().isEmpty ? null : sessionName.trim(),
      clearCustomName: sessionName.trim().isEmpty,
    );
    await BoardTerminalSessionHistory.instance.upsert(
      BoardTerminalSessionEntry(
        id: sessionId,
        sessionName:
            sessionName.trim().isEmpty
                ? current.displayName
                : sessionName.trim(),
        workingDir: current.workspacePath,
        envGroupIds: _envGroupIdsBySession[sessionId] ?? const [],
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      ),
    );
    notifyListeners();
  }

  Future<void> killSession(String sessionId) async {
    SupportLogService.instance.add(
      'terminal-session-manager',
      'killSession sessionId=$sessionId',
    );
    _outputSubs.remove(sessionId)?.cancel();
    _batchFlushTimers.remove(sessionId)?.cancel();
    _batchedOutput.remove(sessionId);
    await _backendService.kill(sessionId);
    final session = _sessions.remove(sessionId);
    if (session != null) {
      await BoardTerminalSessionHistory.instance.upsert(
        BoardTerminalSessionEntry(
          id: session.id,
          sessionName: session.displayName,
          workingDir: session.workspacePath,
          envGroupIds: _envGroupIdsBySession[session.id] ?? const [],
          createdAt: DateTime.now(),
          lastActiveAt: DateTime.now(),
        ),
      );
    }
    _envGroupIdsBySession.remove(sessionId);
    notifyListeners();
  }

  Future<void> deleteSession(String sessionId) async {
    if (isLive(sessionId)) {
      await killSession(sessionId);
    }
    await BoardTerminalSessionHistory.instance.delete(sessionId);
    notifyListeners();
  }

  Future<AgentSession> _spawn({
    required String sessionId,
    required String sessionName,
    required String workingDir,
    required List<String> envGroupIds,
    RemoteBoardInfo? remoteInfo,
    ResourceSessionMetadata? metadata,
  }) async {
    _outputSubs.remove(sessionId)?.cancel();
    _batchFlushTimers.remove(sessionId)?.cancel();
    _batchedOutput.remove(sessionId);
    _envGroupIdsBySession[sessionId] = List<String>.from(envGroupIds);
    final session = AgentSession(
      id: sessionId,
      type: AgentType.terminal,
      workspacePath: workingDir,
      status: AgentStatus.live,
      customName: sessionName,
    );
    final extraEnv = await GlobalEnvGroupsService.instance
        .resolveSelectedGroups(envGroupIds);
    final process = await _backendService.launch(
      sessionId: sessionId,
      workspacePath: workingDir,
      label: session.displayName,
      metadata: metadata,
      extraEnv: extraEnv,
      backendOverride:
          remoteInfo == null
              ? null
              : RemoteYoloitTerminalBackend(remoteInfo: remoteInfo),
    );
    _sessions[sessionId] = session;
    _attachProcess(process, session);
    SupportLogService.instance.add(
      'terminal-session-manager',
      'spawned sessionId=$sessionId workingDir=$workingDir backend=${_backendService.modeFor(sessionId).id}',
    );
    await BoardTerminalSessionHistory.instance.upsert(
      BoardTerminalSessionEntry(
        id: session.id,
        sessionName: session.displayName,
        workingDir: session.workspacePath,
        envGroupIds: envGroupIds,
        createdAt: DateTime.now(),
        lastActiveAt: DateTime.now(),
      ),
    );
    notifyListeners();
    return session;
  }

  void _attachProcess(TerminalProcess process, AgentSession session) {
    final sessionId = session.id;

    void flushBatch() {
      final buf = _batchedOutput.remove(sessionId);
      if (buf == null || buf.isEmpty) return;
      final data = buf.toString();
      session.terminal.write(data);
      session.appendOutput(data);
    }

    void scheduleFlush() {
      _batchFlushTimers[sessionId]?.cancel();
      _batchFlushTimers[sessionId] = Timer(
        const Duration(milliseconds: _batchFlushIntervalMs),
        () {
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        },
      );
    }

    _outputSubs[sessionId] = process.output.listen(
      (data) {
        // Accumulate into batch buffer.
        final buf = _batchedOutput.putIfAbsent(sessionId, StringBuffer.new);
        buf.write(data);

        // Flush immediately if the batch is large, otherwise schedule.
        if (buf.length >= _batchMaxBytes) {
          _batchFlushTimers[sessionId]?.cancel();
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        } else {
          scheduleFlush();
        }
      },
      onDone: () {
        _batchFlushTimers[sessionId]?.cancel();
        _batchFlushTimers.remove(sessionId);
        flushBatch();
        SupportLogService.instance.add(
          'terminal-session-manager',
          'outputStreamDone sessionId=$sessionId',
        );
        _onSessionEnded(sessionId);
      },
      // ignore: avoid_types_on_closure_parameters
      onError: (Object e) {
        _batchFlushTimers[sessionId]?.cancel();
        _batchFlushTimers.remove(sessionId);
        flushBatch();
        SupportLogService.instance.add(
          'terminal-session-manager',
          'outputStreamError sessionId=$sessionId error=$e',
        );
        _onSessionEnded(sessionId);
      },
    );
  }

  void _onSessionEnded(String sessionId) {
    SupportLogService.instance.add(
      'terminal-session-manager',
      'sessionEnded sessionId=$sessionId',
    );
    _outputSubs.remove(sessionId);
    _batchFlushTimers.remove(sessionId)?.cancel();
    _batchedOutput.remove(sessionId);
    _sessions.remove(sessionId);
    notifyListeners();
  }

  /// Attaches a [process] to an existing [session] for testing purposes.
  ///
  /// This bypasses [_spawn] so tests can drive output batching without a real
  /// backend. The manager still owns cleanup (killSession/onDone/onError).
  @visibleForTesting
  void attachProcessForTesting(TerminalProcess process, AgentSession session) {
    _sessions[session.id] = session;
    _attachProcess(process, session);
  }
}
