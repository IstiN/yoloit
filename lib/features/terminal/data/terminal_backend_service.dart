import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

class TerminalBackendService {
  TerminalBackendService._();
  static final instance = TerminalBackendService._();

  final _local = LocalPtyTerminalBackend();
  final _runtime = RuntimeTerminalBackend();
  final _tmux = TmuxTerminalBackend();
  final _bySession = <String, TerminalBackend>{};

  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    Map<String, String>? extraEnv,
  }) async {
    final backend = _selectBackend();
    _bySession[sessionId] = backend;
    return backend.launch(
      sessionId: sessionId,
      workspacePath: workspacePath,
      label: label,
      extraEnv: extraEnv,
    );
  }

  void write(String sessionId, String data) {
    (_bySession[sessionId] ?? _local).write(sessionId, data);
  }

  void resize(String sessionId, int columns, int rows) {
    (_bySession[sessionId] ?? _local).resize(sessionId, columns, rows);
  }

  void kill(String sessionId) {
    (_bySession.remove(sessionId) ?? _local).kill(sessionId);
  }

  TerminalBackendMode modeFor(String sessionId) {
    return _bySession[sessionId]?.mode ?? TerminalBackendMode.local;
  }

  TerminalBackend _selectBackend() {
    return switch (AgentConfigService.instance.terminalBackendMode) {
      TerminalBackendMode.runtime => _runtime,
      TerminalBackendMode.tmux =>
        TmuxService.instance.isActive ? _tmux : _local,
      TerminalBackendMode.local => _local,
    };
  }
}
