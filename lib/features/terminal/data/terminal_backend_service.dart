import 'package:flutter/foundation.dart' show ValueNotifier;
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/services/support_log_service.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/data/runtime_terminal_client.dart';
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
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    TerminalBackend? backendOverride,
  }) async {
    final backend = backendOverride ?? _selectBackend();
    final mode = backend.mode;
    SupportLogService.instance.add(
      'terminal-backend',
      'session=$sessionId mode=${mode.id} label=$label '
      'envKeys=${extraEnv?.keys.toList() ?? const []}',
    );
    _bySession[sessionId] = backend;
    return backend.launch(
      sessionId: sessionId,
      workspacePath: workspacePath,
      label: label,
      metadata: metadata,
      extraEnv: extraEnv,
    );
  }

  void write(String sessionId, String data) {
    final backend = _bySession[sessionId] ?? _local;
    assert(() {
      // ignore: avoid_print
      print('[TerminalBackend] write session=$sessionId backend=${backend.mode.id} dataLen=${data.length}');
      return true;
    }());
    backend.write(sessionId, data);
  }

  void resize(String sessionId, int columns, int rows) {
    (_bySession[sessionId] ?? _local).resize(sessionId, columns, rows);
  }

  Future<void> kill(String sessionId) async {
    await (_bySession.remove(sessionId) ?? _local).kill(sessionId);
  }

  TerminalBackendMode modeFor(String sessionId) {
    return _bySession[sessionId]?.mode ?? TerminalBackendMode.local;
  }

  /// Notifies when the bundled yoloitd binary is newer than the running
  /// runtime process. Only relevant when [TerminalBackendMode.runtime] is used.
  ValueNotifier<bool> get runtimeUpdateRequired => RuntimeTerminalClient.updateRequired;

  /// Kills the current runtime, re-extracts the latest binary, and restarts.
  /// Active terminal sessions will be lost and need manual restart.
  Future<void> restartRuntime() => _runtime.client.restartRuntime();

  TerminalBackend _selectBackend() {
    return switch (AgentConfigService.instance.terminalBackendMode) {
      TerminalBackendMode.runtime => _runtime,
      TerminalBackendMode.tmux =>
        TmuxService.instance.isActive ? _tmux : _local,
      TerminalBackendMode.local => _local,
    };
  }
}
