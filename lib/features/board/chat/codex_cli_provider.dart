import 'dart:async';
import 'dart:convert';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// [ChatProvider] implementation that wraps the OpenAI Codex CLI.
class CodexCliProvider extends CliProviderBase {
  CodexCliProvider({super.agentId = 'codex', super.processStarter});

  @override
  String get debugPrefix => '[CodexCli]';

  @override
  String get displayName => 'Codex';

  @override
  String get defaultLaunchCommand => 'codex';

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool get passSessionArgs => false;

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
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
    List<String> extraCmdArgs = const [],
  }) async {
    final effectiveMessage =
        isFirstMessage
            ? await CliGuidanceService.instance.prependGuidance(
              message,
              runtimeContext: runtimeContext,
            )
            : await CliGuidanceService.instance.prependBoardReminder(
              message,
              runtimeContext: runtimeContext,
            );

    final threadId = isFirstMessage ? null : getSessionId(config.sessionName);

    final optionArgs = <String>[...baseArgs];
    if (config.workingDir.isNotEmpty) {
      optionArgs.addAll(['--cd', config.workingDir]);
    }
    for (final attachment in attachments) {
      optionArgs.addAll(['--image', attachment]);
    }

    if (threadId != null && threadId.isNotEmpty) {
      final resumeOptionArgs = _withoutResumeUnsupportedArgs(optionArgs);
      if (extraCmdArgs.isNotEmpty && extraCmdArgs.first == 'exec') {
        final resumeExtraArgs = _withoutResumeUnsupportedArgs(
          extraCmdArgs.skip(1).toList(),
        );
        return [
          'exec',
          'resume',
          ...resumeExtraArgs,
          ...resumeOptionArgs,
          threadId,
          effectiveMessage,
        ];
      }
      final resumeExtraArgs = _withoutResumeUnsupportedArgs(extraCmdArgs);
      return [
        'exec',
        'resume',
        ...resumeExtraArgs,
        ...resumeOptionArgs,
        threadId,
        effectiveMessage,
      ];
    }
    return [...extraCmdArgs, ...optionArgs, effectiveMessage];
  }

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    final type = json['type'] as String? ?? '';

    if (type == 'thread.started') {
      final threadId = json['thread_id'] as String?;
      if (threadId != null && threadId.isNotEmpty) {
        setSessionId(sessionName, threadId);
      }
      return const [];
    }

    if (type == 'item.completed') {
      final item = json['item'] as Map<String, dynamic>?;
      if (item?['type'] == 'agent_message') {
        final text = item?['text'] as String? ?? '';
        if (text.isEmpty) return const [];
        final id =
            item?['id'] as String? ??
            'codex-${DateTime.now().microsecondsSinceEpoch}';
        return [
          ChatEvent(
            type: ChatEventType.assistantMessage,
            rawType: 'codex.agent_message',
            id: id,
            data: {'messageId': id, 'content': text},
          ),
        ];
      }
      return const [];
    }

    if (type == 'error' || type == 'turn.failed') {
      final message =
          json['message'] as String? ??
          (json['error'] is Map
              ? (json['error'] as Map)['message'] as String?
              : null) ??
          'Codex turn failed';
      throw CliParseError(message);
    }

    if (type == 'turn.completed') {
      final usage = json['usage'] as Map<String, dynamic>?;
      return [
        ChatEvent(
          type: ChatEventType.result,
          rawType: 'codex.result',
          data: {
            'usage': {
              'outputTokens': (usage?['output_tokens'] as num?)?.toInt() ?? 0,
            },
          },
        ),
      ];
    }

    return const [];
  }

  static List<String> _withoutResumeUnsupportedArgs(List<String> args) {
    final result = <String>[];
    for (var i = 0; i < args.length; i++) {
      final arg = args[i];
      if (arg == '--cd' || arg == '-C') {
        if (i + 1 < args.length) i++;
        continue;
      }
      if (arg.startsWith('--cd=') || arg.startsWith('-C=')) {
        continue;
      }
      result.add(arg);
    }
    return result;
  }
}
