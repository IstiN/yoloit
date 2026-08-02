import 'dart:async';
import 'dart:convert';

import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_guidance_service.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

/// Parser for a single Codex `item.*` event payload.
typedef _CodexItemParser =
    List<ChatEvent> Function(
      String type,
      Map<String, dynamic>? item,
      String itemId,
    );

/// [ChatProvider] implementation that wraps the OpenAI Codex CLI.
class CodexCliProvider extends CliProviderBase {
  CodexCliProvider({super.agentId = 'codex', super.processStarter});

  /// Dispatch table for `item.started` / `item.completed` payloads,
  /// keyed by the item's `type` field.
  late final Map<String, _CodexItemParser> _itemParsers = {
    'agent_message': _parseAgentMessageItem,
    'reasoning': _parseReasoningItem,
    'command_execution': _parseCommandExecutionItem,
    'mcp_tool_call': _parseMcpToolCallItem,
    'file_change': _parseFileChangeItem,
  };

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

    if (type == 'item.started' || type == 'item.completed') {
      return _parseItemEvent(type, json);
    }

    if (type == 'error' || type == 'turn.failed') {
      throw CliParseError(_turnFailedMessage(json));
    }

    if (type == 'turn.completed') {
      return _parseTurnCompleted(json);
    }

    return const [];
  }

  String _turnFailedMessage(Map<String, dynamic> json) {
    return json['message'] as String? ??
        (json['error'] is Map
            ? (json['error'] as Map)['message'] as String?
            : null) ??
        'Codex turn failed';
  }

  List<ChatEvent> _parseTurnCompleted(Map<String, dynamic> json) {
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

  List<ChatEvent> _parseItemEvent(String type, Map<String, dynamic> json) {
    final item = json['item'] as Map<String, dynamic>?;
    final itemType = item?['type'] as String? ?? '';
    final itemId = item?['id'] as String? ?? '';
    final parser = _itemParsers[itemType];
    if (parser == null) return const [];
    return parser(type, item, itemId);
  }

  // Agent message – only emit on completed.
  List<ChatEvent> _parseAgentMessageItem(
    String type,
    Map<String, dynamic>? item,
    String itemId,
  ) {
    if (type == 'item.completed') {
      final text = item?['text'] as String? ?? '';
      if (text.isEmpty) return const [];
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'codex.agent_message',
          id: itemId,
          data: {'messageId': itemId, 'content': text},
        ),
      ];
    }
    return const [];
  }

  // Reasoning – emit as assistant message on completed.
  List<ChatEvent> _parseReasoningItem(
    String type,
    Map<String, dynamic>? item,
    String itemId,
  ) {
    if (type == 'item.completed') {
      final text = item?['text'] as String? ?? '';
      if (text.isEmpty) return const [];
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'codex.reasoning',
          id: itemId,
          data: {'messageId': itemId, 'content': text},
        ),
      ];
    }
    return const [];
  }

  // Command execution – map to toolStart / toolComplete.
  List<ChatEvent> _parseCommandExecutionItem(
    String type,
    Map<String, dynamic>? item,
    String itemId,
  ) {
    final command = item?['command'] as String? ?? '';
    if (type == 'item.started') {
      return [
        ChatEvent(
          type: ChatEventType.toolStart,
          rawType: 'codex.command_execution.start',
          id: itemId,
          data: {
            'toolCallId': itemId,
            'toolName': command.isNotEmpty ? command : 'command',
            'arguments': <String, dynamic>{'command': command},
          },
        ),
      ];
    }
    // item.completed
    final output = item?['aggregated_output'] as String? ?? '';
    final exitCode = (item?['exit_code'] as num?)?.toInt();
    final status = item?['status'] as String? ?? '';
    final isSuccess =
        status == 'completed' && (exitCode == null || exitCode == 0);
    return [
      ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'codex.command_execution.complete',
        id: itemId,
        data: {
          'toolCallId': itemId,
          'toolName': command.isNotEmpty ? command : 'command',
          'success': isSuccess,
          'result': {'content': output},
        },
      ),
    ];
  }

  // MCP tool call – map to toolStart / toolComplete.
  List<ChatEvent> _parseMcpToolCallItem(
    String type,
    Map<String, dynamic>? item,
    String itemId,
  ) {
    final server = item?['server'] as String? ?? '';
    final tool = item?['tool'] as String? ?? '';
    final toolName = server.isNotEmpty && tool.isNotEmpty
        ? '$server/$tool'
        : tool.isNotEmpty
        ? tool
        : 'mcp_tool';
    if (type == 'item.started') {
      return [
        ChatEvent(
          type: ChatEventType.toolStart,
          rawType: 'codex.mcp_tool_call.start',
          id: itemId,
          data: {
            'toolCallId': itemId,
            'toolName': toolName,
            'arguments':
                item?['arguments'] as Map<String, dynamic>? ??
                <String, dynamic>{},
          },
        ),
      ];
    }
    // item.completed
    final result = item?['result'] as Map<String, dynamic>?;
    final error = item?['error'] as Map<String, dynamic>?;
    final status = item?['status'] as String? ?? '';
    final isSuccess = status == 'completed' && error == null;
    final resultContent = _extractMcpResult(result);
    return [
      ChatEvent(
        type: ChatEventType.toolComplete,
        rawType: 'codex.mcp_tool_call.complete',
        id: itemId,
        data: {
          'toolCallId': itemId,
          'toolName': toolName,
          'success': isSuccess,
          'result': {'content': resultContent},
        },
      ),
    ];
  }

  // File change – emit as assistant message on completed.
  List<ChatEvent> _parseFileChangeItem(
    String type,
    Map<String, dynamic>? item,
    String itemId,
  ) {
    if (type == 'item.completed') {
      final changes = item?['changes'] as List? ?? [];
      final status = item?['status'] as String? ?? '';
      final buffer = StringBuffer('**File changes** ($status):\n');
      for (final change in changes) {
        if (change is Map) {
          final path = change['path'] as String? ?? '';
          final kind = change['kind'] as String? ?? '';
          buffer.writeln('- `$path` ($kind)');
        }
      }
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'codex.file_change',
          id: itemId,
          data: {'messageId': itemId, 'content': buffer.toString()},
        ),
      ];
    }
    return const [];
  }

  /// Extracts readable text from an MCP tool result payload.
  static String _extractMcpResult(Map<String, dynamic>? result) {
    if (result == null) return '';
    final content = result['content'] as List?;
    if (content != null && content.isNotEmpty) {
      return content
          .map((part) {
            if (part is Map) {
              final text = part['text'];
              if (text is String) return text;
            }
            return jsonEncode(part);
          })
          .join('\n');
    }
    final structured = result['structured_content'];
    if (structured != null) return jsonEncode(structured);
    return '';
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
