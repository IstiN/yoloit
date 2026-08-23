import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
import 'package:yoloit/features/terminal/data/pty_wrapper.dart';
import 'package:yoloit/features/terminal/data/runtime_terminal_client.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

class TerminalProcess {
  TerminalProcess({
    required this.output,
    required this.exitCode,
    this.attachedExisting = false,
  });

  final Stream<String> output;
  final Future<int> exitCode;
  final bool attachedExisting;

  factory TerminalProcess.fromPty(Pty pty) {
    // The facade output is already UTF-8-decoded and ack-flow-controlled
    // (see Pty in pty_wrapper_io.dart).
    return TerminalProcess(
      output: pty.output,
      exitCode: pty.exitCode,
    );
  }

  /// Test seam for the facade ack wrapper: takes the ack as a closure so
  /// tests can count the calls without a real PTY.
  @visibleForTesting
  static Stream<List<int>> ackOnDataForTesting(
    void Function() ackRead,
    Stream<List<int>> source,
  ) =>
      ackOnData(ackRead, source);

  /// Test seam: exercises the buffered UTF-8 decoder without a real PTY.
  @visibleForTesting
  static StreamTransformer<List<int>, String> utf8DecoderForTesting() =>
      const BufferedUtf8Decoder();
}

abstract class TerminalBackend {
  TerminalBackendMode get mode;

  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  });

  void write(String sessionId, String data);

  void resize(String sessionId, int columns, int rows);

  Future<void> kill(String sessionId);
}

class LocalPtyTerminalBackend implements TerminalBackend {
  LocalPtyTerminalBackend({PtyService? ptyService})
    : ptyService = ptyService ?? PtyService.instance;

  final PtyService ptyService;

  @override
  TerminalBackendMode get mode => TerminalBackendMode.local;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  }) async {
    final pty = ptyService.launch(
      sessionId: sessionId,
      workspacePath: workspacePath,
      label: label,
      metadata: metadata,
      extraEnv: extraEnv,
    );
    return TerminalProcess.fromPty(pty);
  }

  @override
  void write(String sessionId, String data) =>
      ptyService.write(sessionId, data);

  @override
  void resize(String sessionId, int columns, int rows) =>
      ptyService.resize(sessionId, columns, rows);

  @override
  Future<void> kill(String sessionId) async => ptyService.kill(sessionId);
}

class TmuxTerminalBackend extends LocalPtyTerminalBackend {
  TmuxTerminalBackend({super.ptyService, TmuxService? tmuxService})
    : _tmuxService = tmuxService ?? TmuxService.instance;

  final TmuxService _tmuxService;

  @override
  TerminalBackendMode get mode => TerminalBackendMode.tmux;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  }) async {
    final pty = ptyService.launchTmux(
      sessionId: sessionId,
      workspacePath: workspacePath,
      tmuxLauncher: _tmuxService.launch,
      label: label,
      metadata: metadata,
      extraEnv: extraEnv,
    );
    if (extraEnv != null && extraEnv.isNotEmpty) {
      await _tmuxService.injectEnv(sessionId, extraEnv);
    }
    return TerminalProcess.fromPty(pty);
  }
}

class RuntimeTerminalBackend implements TerminalBackend {
  RuntimeTerminalBackend({RuntimeTerminalClient? client})
    : _client = client ?? RuntimeTerminalClient();

  final RuntimeTerminalClient _client;

  RuntimeTerminalClient get client => _client;

  @override
  TerminalBackendMode get mode => TerminalBackendMode.runtime;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
    bool forceNewShell = false,
  }) async {
    await _client.ensureStarted();
    final env = _runtimeEnv(extraEnv);
    final shell = PlatformShell.instance.defaultShell;
    var createResult = await _client.createSession(
      sessionId: sessionId,
      cwd: workspacePath,
      command: shell,
      env: env,
    );
    var attachedExisting = createResult.existing;
    // Re-attach to an alive yoloitd session after app restart/update. Only
    // force a fresh shell when the caller explicitly requests it (e.g. env
    // group respawn on the same session id).
    if (attachedExisting && forceNewShell) {
      await _client.kill(sessionId);
      createResult = await _client.createSession(
        sessionId: sessionId,
        cwd: workspacePath,
        command: shell,
        env: env,
      );
      attachedExisting = createResult.existing;
    }
    if (metadata != null) {
      ResourceMonitorService.instance.registerRuntimeShellSession(
        sessionId: sessionId,
        shellPid: createResult.shellPid,
        label: label ?? sessionId,
        metadata: metadata,
      );
    }
    return TerminalProcess(
      output: _client.streamSession(sessionId),
      exitCode: Completer<int>().future,
      attachedExisting: attachedExisting,
    );
  }

  @override
  void write(String sessionId, String data) {
    assert(() {
      // ignore: avoid_print
      print('[RuntimeBackend] input session=$sessionId dataLen=${data.length}');
      return true;
    }());
    _client.input(sessionId, data);
  }

  @override
  void resize(String sessionId, int columns, int rows) =>
      _client.resize(sessionId, columns, rows);

  @override
  Future<void> kill(String sessionId) async {
    ResourceMonitorService.instance.unregisterRuntimeSession(sessionId);
    await _client.kill(sessionId);
  }

  Map<String, String> _runtimeEnv(Map<String, String>? extraEnv) {
    final shell = PlatformShell.instance;
    final merged = <String, String>{
      ...Platform.environment,
      ...?extraEnv,
    };
    final basePath = merged['PATH'] ?? '';
    merged['SHELL'] = shell.defaultShell;
    merged['TERM'] = 'xterm-256color';
    merged['COLORTERM'] = 'truecolor';
    merged['PATH'] = shell.enrichedPath(basePath);
    return {...merged};
  }
}
