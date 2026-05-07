import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// [ChatProvider] implementation that wraps the GitHub Copilot CLI.
///
/// Runs `copilot` with `--output-format json --allow-all` and parses
/// the NDJSON output into [ChatEvent] objects.
class CopilotCliProvider extends ChatProvider {
  CopilotCliProvider();

  final Map<String, Process> _processes = {};
  // Track sessions that have been started in this provider instance.
  // Prevents using --resume for a session that copilot CLI doesn't know about.
  final Set<String> _startedSessions = {};

  @override
  String get providerId => 'copilot';

  @override
  String get displayName => 'GitHub Copilot';

  @override
  List<ChatModelInfo> get availableModels => kCopilotModels;

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool isRunning(String sessionName) => _processes.containsKey(sessionName);

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
  }) {
    final controller = StreamController<ChatEvent>.broadcast();

    _runProcess(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      controller: controller,
    );

    return controller.stream;
  }

  Future<void> _runProcess({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required StreamController<ChatEvent> controller,
  }) async {
    // Kill any existing process for this session
    await stop(config.sessionName);

    final args = <String>[
      '--output-format', 'json',
      '--allow-all',
      '--model', config.model,
    ];

    if (isFirstMessage || !_startedSessions.contains(config.sessionName)) {
      args.addAll(['--name', config.sessionName]);
      _startedSessions.add(config.sessionName);
    } else {
      args.addAll(['--resume', config.sessionName]);
    }

    args.addAll(['-p', message]);

    debugPrint('[CopilotCli] Running: copilot ${args.join(' ')}');
    debugPrint('[CopilotCli] cwd: ${config.workingDir}');

    try {
      final process = await Process.start(
        'copilot',
        args,
        workingDirectory: config.workingDir,
        environment: Platform.environment,
      );
      _processes[config.sessionName] = process;

      // Buffer for incomplete JSON lines
      final buffer = StringBuffer();

      process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              buffer.write(chunk);
              final lines = buffer.toString().split('\n');
              // Keep the last incomplete line in the buffer
              buffer.clear();
              buffer.write(lines.removeLast());

              for (final line in lines) {
                final trimmed = line.trim();
                if (trimmed.isEmpty) continue;
                try {
                  final json = jsonDecode(trimmed) as Map<String, dynamic>;
                  final event = ChatEvent.fromJson(json);
                  controller.add(event);
                } catch (e) {
                  debugPrint('[CopilotCli] Failed to parse line: $trimmed');
                  debugPrint('[CopilotCli] Error: $e');
                }
              }
            },
            onError: (Object error) {
              debugPrint('[CopilotCli] stdout error: $error');
              controller.addError(error);
            },
          );

      process.stderr
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              debugPrint('[CopilotCli] stderr: $chunk');
            },
          );

      final exitCode = await process.exitCode;
      debugPrint('[CopilotCli] Process exited with code: $exitCode');

      // Flush remaining buffer
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        try {
          final json = jsonDecode(remaining) as Map<String, dynamic>;
          controller.add(ChatEvent.fromJson(json));
        } catch (_) {}
      }

      // Only remove if this is still the active process (not replaced by a newer one)
      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      await controller.close();
    } catch (e, st) {
      debugPrint('[CopilotCli] Failed to start process: $e');
      debugPrint('[CopilotCli] Stack: $st');
      controller.addError(e);
      await controller.close();
    }
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process != null) {
      debugPrint('[CopilotCli] Killing process for session: $sessionName');
      process.kill(ProcessSignal.sigterm);
      // Wait for the process to actually exit before returning
      await process.exitCode.timeout(
        const Duration(seconds: 3),
        onTimeout: () => -1,
      );
    }
  }

  @override
  void dispose() {
    for (final process in _processes.values) {
      process.kill(ProcessSignal.sigterm);
    }
    _processes.clear();
  }
}
