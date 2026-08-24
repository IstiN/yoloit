import 'dart:async';
import 'dart:convert';

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
  // One output subscription per session; the element type varies (String for
  // decoded backends, Uint8List for the byte path), hence <void>.
  final Map<String, StreamSubscription<void>> _outputSubs = {};
  final Map<String, List<String>> _envGroupIdsBySession = {};

  // Batched output buffer per session to avoid flooding the xterm
  // [notifyListeners] bridge on every PTY chunk. When a runner dumps
  // thousands of lines per second, each [Terminal.write] triggers a full
  // UI rebuild; batching reduces that to ~20 rebuilds/sec.
  //
  // Chunks are kept as a List<String> of the ORIGINAL chunk references with
  // a running byte counter — a StringBuffer would copy every byte in and
  // then copy the whole 16 KB batch out again on toString().
  final Map<String, List<String>> _batchedOutput = {};
  // Byte-path twin of [_batchedOutput]: raw UTF-8 chunks when the process
  // exposes [TerminalProcess.outputBytes]. A session uses exactly one of the
  // two buffers, picked at attach time.
  final Map<String, List<Uint8List>> _batchedByteOutput = {};
  final Map<String, int> _batchedOutputBytes = {};
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
    _batchedByteOutput.remove(sessionId);
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
    _batchedByteOutput.remove(sessionId);
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
    // Byte-level output is preferred when the backend offers it: the chunks
    // skip the per-KB UTF-8 decode on the UI isolate and are flushed through
    // Terminal.writeBytes, which decodes incrementally itself. Exactly one of
    // the two streams is listened — they wrap the same single-subscription
    // native stream (see Pty.outputBytes).
    final byteStream = process.outputBytes;

    void flushStringBatch() {
      final chunks = _batchedOutput.remove(sessionId);
      _batchedOutputBytes.remove(sessionId);
      if (chunks == null || chunks.isEmpty) return;
      // Ordering is preserved exactly: chunks are written in arrival order.
      for (final chunk in chunks) {
        session.terminal.write(chunk);
      }
      session.appendOutputChunks(chunks);
    }

    void flushByteBatch() {
      final chunks = _batchedByteOutput.remove(sessionId);
      _batchedOutputBytes.remove(sessionId);
      if (chunks == null || chunks.isEmpty) return;
      // Concatenate the batch into ONE buffer so writeBytes runs a single
      // decode+parse pass per flush instead of one per KB-sized PTY chunk.
      // The buffer is freshly allocated and never reused afterwards —
      // writeBytes may retain it when the flush ends mid UTF-8/escape
      // sequence.
      var total = 0;
      for (final chunk in chunks) {
        total += chunk.length;
      }
      final combined = Uint8List(total);
      var offset = 0;
      for (final chunk in chunks) {
        combined.setAll(offset, chunk);
        offset += chunk.length;
      }
      session.terminal.writeBytes(combined);
      // History receives the exact text the String path would have produced:
      // one malformed-tolerant decode of the same bytes.
      session.appendOutputChunks([utf8.decode(combined, allowMalformed: true)]);
    }

    void flushBatch() {
      // Only one of the two buffers is ever non-empty per session.
      flushStringBatch();
      flushByteBatch();
    }

    void scheduleFlush() {
      // Do not reset an already-scheduled flush: recreating the timer on
      // every chunk starves it under continuous output, so the flush ends
      // up running on every 16 KB (full terminal re-raster per flush)
      // instead of ~20 times/sec.
      _batchFlushTimers.putIfAbsent(
        sessionId,
        () => Timer(const Duration(milliseconds: _batchFlushIntervalMs), () {
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        }),
      );
    }

    void handleDone() {
      _batchFlushTimers[sessionId]?.cancel();
      _batchFlushTimers.remove(sessionId);
      flushBatch();
      SupportLogService.instance.add(
        'terminal-session-manager',
        'outputStreamDone sessionId=$sessionId',
      );
      _onSessionEnded(sessionId);
    }

    void handleError(Object e) {
      _batchFlushTimers[sessionId]?.cancel();
      _batchFlushTimers.remove(sessionId);
      flushBatch();
      SupportLogService.instance.add(
        'terminal-session-manager',
        'outputStreamError sessionId=$sessionId error=$e',
      );
      _onSessionEnded(sessionId);
    }

    if (byteStream != null) {
      _outputSubs[sessionId] = byteStream.listen(
        (chunk) {
          // Accumulate into batch buffer (chunk references, no copy).
          final chunks =
              _batchedByteOutput.putIfAbsent(sessionId, () => <Uint8List>[]);
          chunks.add(chunk);
          final bytes = (_batchedOutputBytes[sessionId] ?? 0) + chunk.length;

          // Flush immediately if the batch is large, otherwise schedule.
          if (bytes >= _batchMaxBytes) {
            _batchFlushTimers[sessionId]?.cancel();
            _batchFlushTimers.remove(sessionId);
            flushBatch();
          } else {
            _batchedOutputBytes[sessionId] = bytes;
            scheduleFlush();
          }
        },
        onDone: handleDone,
        onError: handleError,
      );
      return;
    }

    _outputSubs[sessionId] = process.output.listen(
      (data) {
        // Accumulate into batch buffer (chunk references, no copy).
        final chunks = _batchedOutput.putIfAbsent(sessionId, () => <String>[]);
        chunks.add(data);
        final bytes = (_batchedOutputBytes[sessionId] ?? 0) + data.length;

        // Flush immediately if the batch is large, otherwise schedule.
        if (bytes >= _batchMaxBytes) {
          _batchFlushTimers[sessionId]?.cancel();
          _batchFlushTimers.remove(sessionId);
          flushBatch();
        } else {
          _batchedOutputBytes[sessionId] = bytes;
          scheduleFlush();
        }
      },
      onDone: handleDone,
      onError: handleError,
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
    _batchedByteOutput.remove(sessionId);
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
