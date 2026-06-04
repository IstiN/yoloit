import 'dart:async';
import 'dart:convert';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// [ChatProvider] implementation that wraps the Kimi CLI.
class KimiCliProvider extends CliProviderBase {
  KimiCliProvider({super.agentId = 'kimi', super.processStarter});

  @override
  String get debugPrefix => '[KimiCli]';

  @override
  String get displayName => 'Kimi';

  @override
  String get defaultLaunchCommand => 'kimi';

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

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
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
    List<String> extraCmdArgs = const [],
  }) async {
    final configObj = AgentConfigService.instance.configForAgent(agentId);
    final passDefault = configObj?.passDefaultArgs ?? true;

    final args = <String>[...extraCmdArgs, ...baseArgs];

    if (passDefault) {
      if (config.mode == 'plan') {
        args.add('--plan');
      }
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

    return args;
  }

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    final role = json['role'] as String?;

    if (role == 'assistant') {
      final content = _extractText(json['content']);
      if (content.isEmpty) return const [];
      final id = 'kimi-${DateTime.now().microsecondsSinceEpoch}';
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'kimi.assistant',
          id: id,
          data: {'messageId': id, 'content': content},
        ),
      ];
    }

    if (role == 'meta' && json['type'] == 'session.resume_hint') {
      final sessionId = json['session_id'] as String?;
      if (sessionId != null && sessionId.isNotEmpty) {
        storeSessionId(sessionName, sessionId);
      }
      return const [];
    }

    return const [];
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
}
