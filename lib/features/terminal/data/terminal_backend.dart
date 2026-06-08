import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:yoloit/features/terminal/data/pty_wrapper.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/terminal/data/pty_service.dart';
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
    return TerminalProcess(
      output: pty.output.cast<List<int>>().transform(
        const Utf8Decoder(allowMalformed: true),
      ),
      exitCode: pty.exitCode,
    );
  }
}

abstract class TerminalBackend {
  TerminalBackendMode get mode;

  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
  });

  void write(String sessionId, String data);

  void resize(String sessionId, int columns, int rows);

  void kill(String sessionId);
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
  void kill(String sessionId) => ptyService.kill(sessionId);
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

  @override
  TerminalBackendMode get mode => TerminalBackendMode.runtime;

  @override
  Future<TerminalProcess> launch({
    required String sessionId,
    required String workspacePath,
    String? label,
    ResourceSessionMetadata? metadata,
    Map<String, String>? extraEnv,
  }) async {
    await _client.ensureStarted();
    final attachedExisting = await _client.createSession(
      sessionId: sessionId,
      cwd: workspacePath,
      env: _runtimeEnv(extraEnv),
    );
    return TerminalProcess(
      output: _client.streamSession(sessionId),
      exitCode: Completer<int>().future,
      attachedExisting: attachedExisting,
    );
  }

  @override
  void write(String sessionId, String data) => _client.input(sessionId, data);

  @override
  void resize(String sessionId, int columns, int rows) =>
      _client.resize(sessionId, columns, rows);

  @override
  void kill(String sessionId) => _client.kill(sessionId);

  Map<String, String> _runtimeEnv(Map<String, String>? extraEnv) {
    final shell = PlatformShell.instance;
    final merged = <String, String>{...?extraEnv};
    final basePath = merged['PATH'] ?? Platform.environment['PATH'] ?? '';
    merged['TERM'] = 'xterm-256color';
    merged['COLORTERM'] = 'truecolor';
    merged['PATH'] = shell.enrichedPath(basePath);
    return {...merged};
  }
}
