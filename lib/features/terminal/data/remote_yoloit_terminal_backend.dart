import 'dart:async';

import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';

class RemoteYoloitTerminalBackend implements TerminalBackend {
  RemoteYoloitTerminalBackend({required this.remoteInfo})
    : _client = YoloitRemoteClient(
        baseUrl: remoteInfo.url,
        token: remoteInfo.token,
      );

  final RemoteBoardInfo remoteInfo;
  final YoloitRemoteClient _client;
  final Map<String, Timer> _pollers = <String, Timer>{};
  final Map<String, StreamController<String>> _controllers =
      <String, StreamController<String>>{};

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
    await _client.createTerminal(
      id: sessionId,
      cwd: workspacePath,
      env: extraEnv ?? const <String, String>{},
    );
    final controller = StreamController<String>.broadcast();
    final exitCode = Completer<int>();
    _controllers[sessionId] = controller;
    var cursor = 0;
    Future<void> poll() async {
      if (controller.isClosed) return;
      try {
        final log = await _client.terminalLog(sessionId, since: cursor);
        cursor = log.next;
        for (final chunk in log.chunks) {
          if (!controller.isClosed) controller.add(chunk);
        }
        if (!log.running && !controller.isClosed) {
          if (!exitCode.isCompleted) exitCode.complete(log.exitCode ?? 0);
          await controller.close();
          _pollers.remove(sessionId)?.cancel();
        }
      } catch (error, stackTrace) {
        if (!controller.isClosed) controller.addError(error, stackTrace);
      }
    }

    unawaited(poll());
    _pollers[sessionId] = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => unawaited(poll()),
    );
    return TerminalProcess(
      output: controller.stream,
      exitCode: exitCode.future,
    );
  }

  @override
  void write(String sessionId, String data) {
    unawaited(_client.writeTerminal(sessionId, data));
  }

  @override
  void resize(String sessionId, int columns, int rows) {
    // yoloitd remote terminals currently run over stdio, not a PTY.
  }

  @override
  void kill(String sessionId) {
    _pollers.remove(sessionId)?.cancel();
    unawaited(_controllers.remove(sessionId)?.close());
    unawaited(_client.stopTerminal(sessionId));
  }
}
