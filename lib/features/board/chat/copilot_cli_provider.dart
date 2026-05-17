import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// [ChatProvider] implementation that wraps the GitHub Copilot CLI.
///
/// Runs `copilot` with `--output-format json --yolo` and parses
/// the NDJSON output into [ChatEvent] objects.
class CopilotCliProvider extends ChatProvider {
  CopilotCliProvider();

  final Map<String, Process> _processes = {};
  String? _cachedYoloitBin;

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
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
  }) {
    final controller = StreamController<ChatEvent>();

    _runProcess(
      message: message,
      config: config,
      isFirstMessage: isFirstMessage,
      attachments: attachments,
      runtimeContext: runtimeContext,
      controller: controller,
    );

    return controller.stream;
  }

  Future<void> _runProcess({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required StreamController<ChatEvent> controller,
  }) async {
    // Kill any existing process for this session
    await stop(config.sessionName);

    final args = <String>[
      '--output-format',
      'json',
      '--yolo',
      '--model',
      config.model,
    ];

    // Reasoning effort
    if (config.reasoningEffort != null) {
      args.addAll(['--reasoning-effort', config.reasoningEffort!]);
    }

    // Autopilot mode
    if (config.autopilot) {
      args.addAll([
        '--autopilot',
        '--max-autopilot-continues',
        '${config.maxAutopilotContinues}',
      ]);
    }

    // Agent mode
    if (config.mode != null && config.mode!.isNotEmpty) {
      args.addAll(['--mode', config.mode!]);
    }

    // Session name/resume
    if (isFirstMessage) {
      args.addAll(['--name', config.sessionName]);
    } else {
      args.addAll(['--resume', config.sessionName]);
    }

    // Attachments
    for (final path in attachments) {
      args.addAll(['--attachment', path]);
    }

    // Custom args
    args.addAll(config.customArgs);

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;
    final workingDir = _resolveWorkingDir(config.workingDir);

    // Prompt
    args.addAll(['-p', effectiveMessage]);

    debugPrint('[CopilotCli] Running: copilot ${args.join(' ')}');
    debugPrint('[CopilotCli] cwd: $workingDir');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final yoloitBin = _resolveYoloitBin();
      final enrichedPath = _buildSessionPath(
        baseEnv['PATH'] ?? '',
        yoloitBin: yoloitBin,
      );
      final process = await Process.start(
        'copilot',
        args,
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': enrichedPath,
          if (yoloitBin != null) 'YOLOIT_BIN': yoloitBin,
        },
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

      final stderrBuf = StringBuffer();
      process.stderr.transform(utf8.decoder).listen((chunk) {
        debugPrint('[CopilotCli] stderr: $chunk');
        stderrBuf.write(chunk);
      });

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

      // If process exited with error and no events were emitted, surface stderr
      if (exitCode != 0) {
        final errText = stderrBuf.toString().trim();
        controller.addError(
          errText.isNotEmpty ? errText : 'Process exited with code $exitCode',
        );
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

  String _resolveWorkingDir(String configuredDir) {
    final trimmed = configuredDir.trim();
    if (trimmed.isNotEmpty && Directory(trimmed).existsSync()) return trimmed;
    return Directory.current.path;
  }

  String _buildSessionPath(String existingPath, {required String? yoloitBin}) {
    final shell = PlatformShell.instance;
    final entries = <String>[
      if (yoloitBin != null) File(yoloitBin).parent.path,
      ...shell.splitPath(shell.enrichedPath(existingPath)),
    ];
    final deduped = <String>[];
    for (final entry in entries) {
      if (entry.isEmpty || deduped.contains(entry)) continue;
      deduped.add(entry);
    }
    return shell.joinPath(deduped);
  }

  String? _resolveYoloitBin() {
    final cached = _cachedYoloitBin;
    if (cached != null && File(cached).existsSync()) return cached;

    // Check the installed location first — written by CliServer on startup.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final installed = File('$home/.config/yoloit/yoloit');
      if (installed.existsSync()) {
        _cachedYoloitBin = installed.path;
        return installed.path;
      }
    }

    final roots = <Directory>[];
    void addRoot(String path) {
      if (path.isEmpty) return;
      final dir = Directory(path).absolute;
      if (roots.any((existing) => existing.path == dir.path)) return;
      roots.add(dir);
    }

    addRoot(Directory.current.path);
    addRoot(File(Platform.resolvedExecutable).parent.path);

    for (final root in roots) {
      var current = root;
      for (var depth = 0; depth < 6; depth++) {
        final candidate = File(
          '${current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}yoloit',
        );
        if (candidate.existsSync()) {
          _cachedYoloitBin = candidate.path;
          return candidate.path;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return null;
  }
}
