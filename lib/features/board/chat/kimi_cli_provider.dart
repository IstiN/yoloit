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

    // Assistant message (may contain tool_calls).
    if (role == 'assistant') {
      final content = _extractText(json['content']);
      final toolCalls = _extractToolCalls(json['tool_calls']);
      final id = 'kimi-${DateTime.now().microsecondsSinceEpoch}';
      final events = <ChatEvent>[];

      // Emit toolStart for each requested tool call so the UI shows a
      // running card before the tool result arrives.
      for (final tc in toolCalls) {
        final tcId = tc['toolCallId'] as String? ?? '';
        events.add(
          ChatEvent(
            type: ChatEventType.toolStart,
            rawType: 'kimi.tool_call.start',
            id: tcId,
            data: {
              'toolCallId': tcId,
              'toolName': tc['name'] as String? ?? '',
              'arguments': tc['arguments'],
            },
          ),
        );
      }

      events.add(
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'kimi.assistant',
          id: id,
          data: {
            'messageId': id,
            'content': content,
            if (toolCalls.isNotEmpty) 'toolRequests': toolCalls,
          },
        ),
      );
      return events;
    }

    // Tool result message.
    if (role == 'tool') {
      final content = _extractText(json['content']);
      final toolCallId = json['tool_call_id'] as String? ?? '';
      final isError = content.contains('<system>ERROR:');
      return [
        ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'kimi.tool',
          id: toolCallId,
          data: {
            'toolCallId': toolCallId,
            'toolName': '',
            'success': !isError,
            'result': {'content': content},
          },
        ),
      ];
    }

    // System notification (no role field).
    if (json['category'] is String || json['severity'] is String) {
      final title = json['title'] as String? ?? '';
      final body = json['body'] as String? ?? '';
      if (title.isNotEmpty || body.isNotEmpty) {
        return [
          ChatEvent(
            type: ChatEventType.sessionStatus,
            rawType: 'kimi.notification',
            data: {'title': title, 'body': body},
          ),
        ];
      }
      return const [];
    }

    // Plan display (no role field).
    if (json['file_path'] is String && json['content'] != null) {
      final planContent = json['content'] as String? ?? '';
      final planId = 'kimi-plan-${DateTime.now().microsecondsSinceEpoch}';
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'kimi.plan',
          id: planId,
          data: {'messageId': planId, 'content': planContent},
        ),
      ];
    }

    // Legacy meta event for session resumption (kept for backwards compat).
    if (role == 'meta' && json['type'] == 'session.resume_hint') {
      final sessionId = json['session_id'] as String?;
      if (sessionId != null && sessionId.isNotEmpty) {
        storeSessionId(sessionName, sessionId);
      }
      return const [];
    }

    return const [];
  }

  /// Extracts plain text from Kimi message content.
  /// Content may be a single string or a list of content parts.
  /// Thinking parts (type: "think") are included as a quoted block.
  String _extractText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      final textParts = <String>[];
      final thinkParts = <String>[];
      for (final part in content) {
        if (part is String) {
          textParts.add(part);
          continue;
        }
        if (part is Map) {
          final text = part['text'];
          if (text is String && text.isNotEmpty) {
            textParts.add(text);
            continue;
          }
          final think = part['think'];
          if (think is String && think.isNotEmpty) {
            thinkParts.add(think);
          }
        }
      }
      final result = <String>[];
      if (thinkParts.isNotEmpty) {
        final thinking = thinkParts.join();
        result.add('> **Thinking**\n');
        for (final line in thinking.split('\n')) {
          result.add('> $line\n');
        }
        result.add('\n');
      }
      result.addAll(textParts);
      return result.join();
    }
    return '';
  }

  /// Converts kosong-style tool_calls into the yoloit toolRequests format.
  List<Map<String, dynamic>> _extractToolCalls(Object? toolCallsJson) {
    if (toolCallsJson is! List) return const [];
    return toolCallsJson
        .whereType<Map<String, dynamic>>()
        .map((tc) {
          final id = tc['id'] as String? ?? '';
          final function = tc['function'] as Map<String, dynamic>?;
          final name = function?['name'] as String? ?? '';
          final argumentsStr = function?['arguments'] as String? ?? '{}';
          Map<String, dynamic> args;
          try {
            args = jsonDecode(argumentsStr) as Map<String, dynamic>;
          } catch (_) {
            args = <String, dynamic>{};
          }
          return <String, dynamic>{
            'toolCallId': id,
            'name': name,
            'arguments': args,
          };
        })
        .where(
          (tc) =>
              tc['toolCallId'] != null &&
              (tc['toolCallId'] as String).isNotEmpty,
        )
        .toList();
  }
}
