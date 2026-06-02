import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_resource_registration.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

typedef KimiProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

class KimiCliProvider extends ChatProvider {
  KimiCliProvider({this.agentId = 'kimi', KimiProcessStarter? processStarter})
    : _processStarter = processStarter ?? _defaultProcessStarter;

  final String agentId;
  final KimiProcessStarter _processStarter;
  final Map<String, Process> _processes = {};
  final Map<String, String> _sessionIds = {};

  @override
  String get providerId => agentId;

  @override
  String get displayName => 'Kimi';

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    return kKimiModels;
  }

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
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    // ignore: close_sinks - closed by _runProcess after the CLI exits.
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
    await stop(config.sessionName);

    final configObj = AgentConfigService.instance.configForAgent(agentId);
    final passDefault = configObj?.passDefaultArgs ?? true;
    final args = <String>[];
    if (passDefault) {
      if (!(configObj?.disableModel ?? false) && config.model.isNotEmpty) {
        args.addAll(['--model', config.model]);
      }
      if (!isFirstMessage) {
        final sessionId = _sessionIds[config.sessionName];
        if (sessionId != null && sessionId.isNotEmpty) {
          args.addAll(['--session', sessionId]);
        }
      }
      if (config.mode == 'plan') {
        args.add('--plan');
      }
      args.addAll(config.customArgs);
    }

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;
    final prompt =
        attachments.isEmpty
            ? effectiveMessage
            : '$effectiveMessage\n\nAttachments:\n${attachments.join('\n')}';
    args.addAll(['-p', prompt]);

    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty || rawCommand == 'kimi') {
      rawCommand = AgentConfigService.defaultBoardChatCommand('kimi');
    }
    final cmdParts = _splitCommand(rawCommand);
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : 'kimi';
    final extraCmdArgs = cmdParts.length > 1 ? cmdParts.sublist(1) : <String>[];
    final workingDir = _resolveWorkingDir(config.workingDir);

    debugPrint(
      '[KimiCli] Running: $executable ${[...extraCmdArgs, ...args].join(' ')}',
    );
    debugPrint('[KimiCli] cwd: $workingDir');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final process = await _processStarter(
        executable,
        [...extraCmdArgs, ...args],
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': PlatformShell.instance.enrichedPath(baseEnv['PATH'] ?? ''),
        },
      );
      _processes[config.sessionName] = process;
      registerChatProcessResource(
        process: process,
        providerId: agentId,
        config: config,
        runtimeContext: runtimeContext,
      );
      unawaited(
        process.stdin.close().catchError((Object error) {
          debugPrint('[KimiCli] Failed to close stdin: $error');
        }),
      );

      final buffer = StringBuffer();
      final stdoutDone = Completer<void>();
      process.stdout
          .transform(utf8.decoder)
          .listen(
            (chunk) {
              buffer.write(chunk);
              final lines = buffer.toString().split('\n');
              buffer.clear();
              buffer.write(lines.removeLast());
              for (final line in lines) {
                _handleLine(line, config.sessionName, controller);
              }
            },
            onError: (Object error) {
              if (!controller.isClosed) controller.addError(error);
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
            onDone: () {
              if (!stdoutDone.isCompleted) stdoutDone.complete();
            },
          );

      final stderrBuffer = StringBuffer();
      final stderrDone = Completer<void>();
      process.stderr
          .transform(utf8.decoder)
          .listen(
            stderrBuffer.write,
            onDone: () {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
            onError: (_) {
              if (!stderrDone.isCompleted) stderrDone.complete();
            },
          );

      final exitCode = await process.exitCode;
      await stdoutDone.future;
      await stderrDone.future;
      final remaining = buffer.toString().trim();
      if (remaining.isNotEmpty) {
        _handleLine(remaining, config.sessionName, controller);
      }
      if (exitCode != 0 && !controller.isClosed) {
        final stderr = stderrBuffer.toString().trim();
        controller.addError(
          stderr.isNotEmpty ? stderr : 'Kimi exited with code $exitCode',
        );
      }
      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      unregisterChatProcessResource(process);
      await controller.close();
    } catch (error, stack) {
      debugPrint('[KimiCli] Failed to start process: $error');
      debugPrint('[KimiCli] Stack: $stack');
      if (!controller.isClosed) controller.addError(error);
      await controller.close();
    }
  }

  void _handleLine(
    String line,
    String sessionName,
    StreamController<ChatEvent> controller,
  ) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return;
    try {
      final json = jsonDecode(trimmed) as Map<String, dynamic>;
      final role = json['role'] as String?;
      if (role == 'assistant') {
        final content = _extractText(json['content']);
        if (content.isEmpty) return;
        final id = 'kimi-${DateTime.now().microsecondsSinceEpoch}';
        controller.add(
          ChatEvent(
            type: ChatEventType.assistantMessage,
            rawType: 'kimi.assistant',
            id: id,
            data: {'messageId': id, 'content': content},
          ),
        );
        return;
      }
      if (role == 'meta' && json['type'] == 'session.resume_hint') {
        final sessionId = json['session_id'] as String?;
        if (sessionId != null && sessionId.isNotEmpty) {
          _sessionIds[sessionName] = sessionId;
        }
      }
    } catch (error) {
      debugPrint('[KimiCli] Failed to parse line: $trimmed');
      debugPrint('[KimiCli] Error: $error');
    }
  }

  String _extractText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .map((part) {
            if (part is String) return part;
            if (part is Map) {
              final text = part['text'];
              if (text is String) return text;
            }
            return '';
          })
          .where((text) => text.isNotEmpty)
          .join();
    }
    return '';
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process == null) return;
    unregisterChatProcessResource(process);
    process.kill(ProcessSignal.sigterm);
    await process.exitCode.timeout(
      const Duration(seconds: 2),
      onTimeout: () {
        process.kill(ProcessSignal.sigkill);
        return -1;
      },
    );
  }

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _sessionIds[sessionName];

  @override
  void dispose() {
    for (final process in _processes.values) {
      unregisterChatProcessResource(process);
      process.kill(ProcessSignal.sigterm);
    }
    _processes.clear();
    _sessionIds.clear();
  }

  @override
  void detach() {
    _processes.clear();
  }

  String _resolveWorkingDir(String configuredDir) {
    final trimmed = configuredDir.trim();
    if (trimmed.isNotEmpty && Directory(trimmed).existsSync()) return trimmed;
    return Directory.current.path;
  }
}

Future<Process> _defaultProcessStarter(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
}) {
  return Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    environment: environment,
  );
}

List<String> _splitCommand(String command) {
  final parts = <String>[];
  final buffer = StringBuffer();
  var inSingle = false;
  var inDouble = false;
  for (var i = 0; i < command.length; i++) {
    final char = command[i];
    if (char == "'" && !inDouble) {
      inSingle = !inSingle;
      continue;
    }
    if (char == '"' && !inSingle) {
      inDouble = !inDouble;
      continue;
    }
    if (char.trim().isEmpty && !inSingle && !inDouble) {
      if (buffer.isNotEmpty) {
        parts.add(buffer.toString());
        buffer.clear();
      }
      continue;
    }
    buffer.write(char);
  }
  if (buffer.isNotEmpty) parts.add(buffer.toString());
  return parts;
}
