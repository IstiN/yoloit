import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

typedef CodexProcessStarter =
    Future<Process> Function(
      String executable,
      List<String> arguments, {
      String? workingDirectory,
      Map<String, String>? environment,
    });

class CodexCliProvider extends ChatProvider {
  CodexCliProvider({
    this.agentId = 'codex',
    CodexProcessStarter? processStarter,
  }) : _processStarter = processStarter ?? _defaultProcessStarter;

  final String agentId;
  final CodexProcessStarter _processStarter;
  final Map<String, Process> _processes = {};
  final Map<String, String> _threadIds = {};

  @override
  String get providerId => agentId;

  @override
  String get displayName => 'Codex';

  @override
  List<ChatModelInfo> get availableModels {
    final catalogModels = ProviderModelCatalogService.instance
        .modelsForProvider(agentId);
    if (catalogModels != null && catalogModels.isNotEmpty) {
      return catalogModels;
    }
    return kCodexModels;
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
    final optionArgs = <String>[];
    if (passDefault) {
      if (!(configObj?.disableModel ?? false) && config.model.isNotEmpty) {
        optionArgs.addAll(['--model', config.model]);
      }
      if (config.workingDir.isNotEmpty) {
        optionArgs.addAll(['--cd', config.workingDir]);
      }
      for (final attachment in attachments) {
        optionArgs.addAll(['--image', attachment]);
      }
      optionArgs.addAll(config.customArgs);
    }

    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : message;

    var rawCommand = configObj?.launchCommand.trim() ?? '';
    if (rawCommand.isEmpty || rawCommand == 'codex') {
      rawCommand = AgentConfigService.defaultBoardChatCommand('codex');
    }
    final cmdParts = _splitCommand(rawCommand);
    final executable = cmdParts.isNotEmpty ? cmdParts[0] : 'codex';
    final extraCmdArgs = cmdParts.length > 1 ? cmdParts.sublist(1) : <String>[];
    final args = _buildArgs(
      extraCmdArgs: extraCmdArgs,
      optionArgs: optionArgs,
      prompt: effectiveMessage,
      threadId: isFirstMessage ? null : _threadIds[config.sessionName],
    );
    final workingDir = _resolveWorkingDir(config.workingDir);

    debugPrint('[CodexCli] Running: $executable ${args.join(' ')}');
    debugPrint('[CodexCli] cwd: $workingDir');

    try {
      final extraEnv = await GlobalEnvGroupsService.instance
          .resolveSelectedGroups(config.envGroupIds);
      final baseEnv = {...Platform.environment, ...extraEnv};
      final process = await _processStarter(
        executable,
        args,
        workingDirectory: workingDir,
        environment: {
          ...baseEnv,
          'PATH': PlatformShell.instance.enrichedPath(baseEnv['PATH'] ?? ''),
        },
      );
      _processes[config.sessionName] = process;

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
          stderr.isNotEmpty ? stderr : 'Codex exited with code $exitCode',
        );
      }
      if (_processes[config.sessionName] == process) {
        _processes.remove(config.sessionName);
      }
      await controller.close();
    } catch (error, stack) {
      debugPrint('[CodexCli] Failed to start process: $error');
      debugPrint('[CodexCli] Stack: $stack');
      if (!controller.isClosed) controller.addError(error);
      await controller.close();
    }
  }

  List<String> _buildArgs({
    required List<String> extraCmdArgs,
    required List<String> optionArgs,
    required String prompt,
    required String? threadId,
  }) {
    if (threadId != null && threadId.isNotEmpty) {
      if (extraCmdArgs.isNotEmpty && extraCmdArgs.first == 'exec') {
        return [
          'exec',
          'resume',
          ...extraCmdArgs.skip(1),
          ...optionArgs,
          threadId,
          prompt,
        ];
      }
      return [
        'exec',
        'resume',
        ...extraCmdArgs,
        ...optionArgs,
        threadId,
        prompt,
      ];
    }
    return [...extraCmdArgs, ...optionArgs, prompt];
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
      final type = json['type'] as String? ?? '';
      if (type == 'thread.started') {
        final threadId = json['thread_id'] as String?;
        if (threadId != null && threadId.isNotEmpty) {
          _threadIds[sessionName] = threadId;
        }
        return;
      }
      if (type == 'item.completed') {
        final item = json['item'] as Map<String, dynamic>?;
        if (item?['type'] == 'agent_message') {
          final text = item?['text'] as String? ?? '';
          if (text.isEmpty) return;
          final id =
              item?['id'] as String? ??
              'codex-${DateTime.now().microsecondsSinceEpoch}';
          controller.add(
            ChatEvent(
              type: ChatEventType.assistantMessage,
              rawType: 'codex.agent_message',
              id: id,
              data: {'messageId': id, 'content': text},
            ),
          );
        }
        return;
      }
      if (type == 'error' || type == 'turn.failed') {
        final message =
            json['message'] as String? ??
            (json['error'] is Map
                ? (json['error'] as Map)['message'] as String?
                : null) ??
            'Codex turn failed';
        controller.addError(message);
        return;
      }
      if (type == 'turn.completed') {
        final usage = json['usage'] as Map<String, dynamic>?;
        controller.add(
          ChatEvent(
            type: ChatEventType.result,
            rawType: 'codex.result',
            data: {
              'usage': {
                'outputTokens': (usage?['output_tokens'] as num?)?.toInt() ?? 0,
              },
            },
          ),
        );
      }
    } catch (error) {
      debugPrint('[CodexCli] Failed to parse line: $trimmed');
      debugPrint('[CodexCli] Error: $error');
    }
  }

  @override
  Future<void> stop(String sessionName) async {
    final process = _processes.remove(sessionName);
    if (process == null) return;
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
    _threadIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _threadIds[sessionName];

  @override
  void dispose() {
    for (final process in _processes.values) {
      process.kill(ProcessSignal.sigterm);
    }
    _processes.clear();
    _threadIds.clear();
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
