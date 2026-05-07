import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

class BoardTerminalSessionManager extends ChangeNotifier {
  BoardTerminalSessionManager._();

  static final instance = BoardTerminalSessionManager._();

  final _ptyService = PtyService.instance;
  final Map<String, AgentSession> _sessions = {};
  final Map<String, StreamSubscription<String>> _outputSubs = {};
  final Map<String, List<String>> _envGroupIdsBySession = {};

  AgentSession? sessionFor(String id) => _sessions[id];
  bool isLive(String id) => _sessions.containsKey(id);

  Future<AgentSession> ensureSession(BoardTerminalConfig config) async {
    final existing = _sessions[config.sessionId];
    if (existing != null) return existing;
    return _spawn(
      sessionId: config.sessionId,
      sessionName: config.sessionName,
      workingDir: config.workingDir,
      envGroupIds: config.envGroupIds,
    );
  }

  Future<AgentSession> createSession({
    required String sessionName,
    required String workingDir,
    List<String> envGroupIds = const [],
  }) async {
    final sessionId = 'board_terminal_${DateTime.now().millisecondsSinceEpoch}';
    return _spawn(
      sessionId: sessionId,
      sessionName: sessionName,
      workingDir: workingDir,
      envGroupIds: envGroupIds,
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
    _outputSubs.remove(sessionId)?.cancel();
    _ptyService.kill(sessionId);
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
  }) async {
    _outputSubs.remove(sessionId)?.cancel();
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
    final pty = _ptyService.launch(
      sessionId: sessionId,
      workspacePath: workingDir,
      label: session.displayName,
      extraEnv: extraEnv,
    );
    _sessions[sessionId] = session;
    _attachPty(pty, session);
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

  void _attachPty(Pty pty, AgentSession session) {
    _outputSubs[session.id] = pty.output
        .cast<List<int>>()
        .transform(const Utf8Decoder(allowMalformed: true))
        .listen(
          (data) {
            session.terminal.write(data);
            session.appendOutput(data);
          },
          onDone: () => _onSessionEnded(session.id),
          onError: (_) => _onSessionEnded(session.id),
        );
  }

  void _onSessionEnded(String sessionId) {
    _outputSubs.remove(sessionId);
    _sessions.remove(sessionId);
    notifyListeners();
  }
}
