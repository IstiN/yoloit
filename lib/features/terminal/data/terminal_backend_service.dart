import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier, visibleForTesting;
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

  // ── Write coalescing ───────────────────────────────────────────────
  // Rapid 1-byte writes (keystrokes) are batched into a single
  // backend.write call, flushed after [_writeFlushMs] or when a
  // multi-byte write arrives (paste, control sequence). This reduces
  // per-char syscall + log overhead, especially under load.
  static const _writeFlushMs = 2;
  final _writeBuf = <String, StringBuffer>{};
  final _writeTimers = <String, Timer>{};

  /// Test-only backend override: when set, [launch] always uses it instead of
  /// selecting a real local/runtime/tmux backend (which would spawn processes).
  @visibleForTesting
  TerminalBackend? debugBackendOverride;

  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    TerminalBackend? backendOverride,
    bool forceNewShell = false,
  }) async {
    final backend = backendOverride ?? _selectBackend();
    final mode = backend.mode;
    SupportLogService.instance.add(
      'terminal-backend',
      'session=$sessionId mode=${mode.id} label=$label '
      'envKeys=${extraEnv?.keys.toList() ?? const []} '
      'forceNewShell=$forceNewShell',
    );
    _bySession[sessionId] = backend;
    return backend.launch(
      sessionId: sessionId,
      workspacePath: workspacePath,
      label: label,
      metadata: metadata,
      extraEnv: extraEnv,
      forceNewShell: forceNewShell,
    );
  }

  void write(String sessionId, String data) {
    // Multi-byte writes (paste, control sequences, resize response) flush
    // the buffer immediately, then write synchronously to preserve ordering.
    if (data.length > 1) {
      _flushWrite(sessionId);
      _doWrite(sessionId, data);
      return;
    }
    // Single-byte writes (keystrokes) are coalesced.
    (_writeBuf[sessionId] ??= StringBuffer()).write(data);
    _writeTimers[sessionId] ??= Timer(
      const Duration(milliseconds: _writeFlushMs),
      () => _flushWrite(sessionId),
    );
  }

  void _flushWrite(String sessionId) {
    final timer = _writeTimers.remove(sessionId);
    timer?.cancel();
    final buf = _writeBuf.remove(sessionId);
    if (buf == null || buf.isEmpty) return;
    _doWrite(sessionId, buf.toString());
  }

  void _doWrite(String sessionId, String data) {
    final backend = _bySession[sessionId] ?? _local;
    SupportLogService.instance.add(
      'terminal-backend',
      'write session=$sessionId backend=${backend.mode.id} dataLen=${data.length}',
    );
    backend.write(sessionId, data);
  }

  void resize(String sessionId, int columns, int rows) {
    final backend = _bySession[sessionId] ?? _local;
    SupportLogService.instance.add(
      'terminal-backend',
      'resize session=$sessionId backend=${backend.mode.id} cols=$columns rows=$rows',
    );
    backend.resize(sessionId, columns, rows);
  }

  Future<void> kill(String sessionId) async {
    _flushWrite(sessionId);
    SupportLogService.instance.add(
      'terminal-backend',
      'kill session=$sessionId backend=${(_bySession[sessionId] ?? _local).mode.id}',
    );
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
    final override = debugBackendOverride;
    if (override != null) return override;
    return switch (AgentConfigService.instance.terminalBackendMode) {
      TerminalBackendMode.runtime => _runtime,
      TerminalBackendMode.tmux =>
        TmuxService.instance.isActive ? _tmux : _local,
      TerminalBackendMode.local => _local,
    };
  }
}
