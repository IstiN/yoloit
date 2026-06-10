import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/assistant_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/chat_ask_user_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_system_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/tool_result_card.dart';
import 'package:yoloit/features/board/chat/widgets/user_bubble.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// A reusable molecule that renders a [ChatMessage] according to its role.
///
/// Extracted from [ChatMessageList] so that debug showcases and other
/// consumers can render chat bubbles without depending on the full chat panel.
class ChatMessageMolecule extends StatelessWidget {
  const ChatMessageMolecule({
    required this.message,
    this.activeToolCalls = const {},
    this.subAgentPanels = const {},
    this.isIgnoredToolCall,
    this.isSubAgentToolCall,
    this.onLinkTap,
    this.onOpenFile,
    this.onSendToPanel,
    this.onAskUserChoice,
    this.onFocusPanel,
    super.key,
  });

  final ChatMessage message;
  final Map<String, ChatToolCall> activeToolCalls;
  final Map<String, String> subAgentPanels;
  final bool Function(String)? isIgnoredToolCall;
  final bool Function(String)? isSubAgentToolCall;
  final ValueChanged<String?>? onLinkTap;
  final ValueChanged<String>? onOpenFile;
  final void Function({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String content,
  })? onSendToPanel;
  final ValueChanged<String>? onAskUserChoice;
  final ValueChanged<String>? onFocusPanel;

  static String _resolveToolName(String? toolName, {String? content}) {
    final raw = toolName?.trim() ?? '';
    final normalized = raw.toLowerCase();
    if (normalized.isNotEmpty && normalized != 'unknown') return raw;
    final text = content?.trim().toLowerCase() ?? '';
    if (text == 'intent logged') return 'report_intent';
    return raw.isEmpty ? 'unknown' : raw;
  }

  bool _isIgnored(String name) => isIgnoredToolCall?.call(name) ?? false;

  bool _isSubAgent(String name) => isSubAgentToolCall?.call(name) ?? false;

  @override
  Widget build(BuildContext context) {
    switch (message.role) {
      case ChatRole.user:
        return UserBubble(
          content: message.content,
          attachments: message.attachments,
          onOpenFile: onOpenFile,
        );

      case ChatRole.assistant:
        final visibleToolCalls = message.toolCalls
            .map(
              (tc) => tc.copyWith(
                toolName: _resolveToolName(tc.toolName, content: tc.result),
              ),
            )
            .where((tc) => !_isIgnored(tc.toolName))
            .toList();
        return AssistantBubble(
          content: message.content,
          toolCalls: visibleToolCalls,
          tokenUsage: message.tokenUsage,
          onLinkTap: onLinkTap,
          onOpenFile: onOpenFile,
        );

      case ChatRole.tool:
        final resolvedToolName = _resolveToolName(
          message.toolName,
          content: message.content,
        );
        if (_isIgnored(resolvedToolName)) {
          return const SizedBox.shrink();
        }
        final persistedSuccess = message.metadata?['success'] as bool?;
        final toolArgs = activeToolCalls[message.toolCallId]?.arguments ?? {};
        return ToolResultCard(
          toolName: resolvedToolName,
          toolCallId: message.toolCallId ?? '',
          content: message.content,
          success:
              activeToolCalls[message.toolCallId]?.success ?? persistedSuccess,
          onSendToPanel:
              message.content.isNotEmpty && onSendToPanel != null
                  ? () => onSendToPanel!(
                        toolName: resolvedToolName,
                        arguments: toolArgs,
                        content: message.content,
                      )
                  : null,
          onOpenAgentPanel:
              _isSubAgent(resolvedToolName) &&
                      subAgentPanels.containsKey(message.toolCallId) &&
                      onFocusPanel != null
                  ? () => onFocusPanel!(subAgentPanels[message.toolCallId]!)
                  : null,
        );

      case ChatRole.system:
        final meta = message.metadata;
        if (meta != null && meta['type'] == 'ask_user') {
          return ChatAskUserCard(
            question: message.content,
            choices: (meta['choices'] as List?)?.cast<String>() ?? [],
            onChoice: onAskUserChoice ?? (_) {},
          );
        }
        return ChatSystemBubble(content: message.content);
    }
  }
}
