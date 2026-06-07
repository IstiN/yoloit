import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/chat/widgets/assistant_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/chat_ask_user_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_running_tools_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_system_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';
import 'package:yoloit/features/board/chat/widgets/streaming_bubble.dart';
import 'package:yoloit/features/board/chat/widgets/tool_result_card.dart';
import 'package:yoloit/features/board/chat/widgets/user_bubble.dart';

class ChatMessageList extends StatelessWidget {
  const ChatMessageList({
    super.key,
    required this.messages,
    required this.activeToolCalls,
    required this.streamingContent,
    required this.isProcessing,
    required this.scrollController,
    required this.subAgents,
    required this.subAgentPanels,
    required this.isIgnoredToolCall,
    required this.isSubAgentToolCall,
    required this.onLinkTap,
    required this.onOpenFile,
    required this.onSendToPanel,
    required this.onAskUserChoice,
    required this.onSendMessage,
  });

  final List<ChatMessage> messages;
  final Map<String, ChatToolCall> activeToolCalls;
  final String streamingContent;
  final bool isProcessing;
  final ScrollController scrollController;
  final Map<String, SubAgentRunState> subAgents;
  final Map<String, String> subAgentPanels;
  final bool Function(String) isIgnoredToolCall;
  final bool Function(String) isSubAgentToolCall;
  final ValueChanged<String?>? onLinkTap;
  final ValueChanged<String> onOpenFile;
  final void Function({
    required String toolName,
    required Map<String, dynamic> arguments,
    required String content,
  }) onSendToPanel;
  final ValueChanged<String> onAskUserChoice;
  final VoidCallback onSendMessage;

  static String _resolveToolName(String? toolName, {String? content}) {
    final raw = toolName?.trim() ?? '';
    final normalized = raw.toLowerCase();
    if (normalized.isNotEmpty && normalized != 'unknown') return raw;
    final text = content?.trim().toLowerCase() ?? '';
    if (text == 'intent logged') return 'report_intent';
    return raw.isEmpty ? 'unknown' : raw;
  }

  @override
  Widget build(BuildContext context) {
    final runningTools =
        activeToolCalls.values
            .where((t) => t.isRunning && !isIgnoredToolCall(t.toolName))
            .toList();
    final hasRunningTools = runningTools.isNotEmpty;
    final showStreaming = streamingContent.isNotEmpty;
    final showThinking = isProcessing && !showStreaming && !hasRunningTools;

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      itemCount:
          messages.length +
          (showStreaming ? 1 : 0) +
          (hasRunningTools ? 1 : 0) +
          (showThinking ? 1 : 0),
      itemBuilder: (context, index) {
        if (index < messages.length) {
          return _buildMessageBubble(context, messages[index]);
        }

        final extra = index - messages.length;

        if (hasRunningTools && extra == 0) {
          return ChatRunningToolsCard(
            tools: runningTools,
            subAgents: subAgents,
            subAgentPanels: subAgentPanels,
            isSubAgentToolCall: isSubAgentToolCall,
            onFocusPanel: (panelId) {
              context.read<BoardCubit>().focusPanel(panelId);
            },
          );
        }

        if (showStreaming) {
          return StreamingBubble(
            content: streamingContent,
            onLinkTap: onLinkTap,
          );
        }

        if (showThinking) {
          return Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appColors.surfaceElevated,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                ),
              ),
              child: const ChatTypingIndicator(),
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    switch (message.role) {
      case ChatRole.user:
        return UserBubble(
          content: message.content,
          attachments: message.attachments,
          onOpenFile: onOpenFile,
        );
      case ChatRole.assistant:
        final visibleToolCalls =
            message.toolCalls
                .map(
                  (tc) => tc.copyWith(
                    toolName: _resolveToolName(tc.toolName, content: tc.result),
                  ),
                )
                .where((tc) => !isIgnoredToolCall(tc.toolName))
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
        if (isIgnoredToolCall(resolvedToolName)) {
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
              message.content.isNotEmpty
                  ? () => onSendToPanel(
                        toolName: resolvedToolName,
                        arguments: toolArgs,
                        content: message.content,
                      )
                  : null,
          onOpenAgentPanel:
              isSubAgentToolCall(resolvedToolName) &&
                      subAgentPanels.containsKey(message.toolCallId)
                  ? () => context.read<BoardCubit>().focusPanel(
                    subAgentPanels[message.toolCallId]!,
                  )
                  : null,
        );
      case ChatRole.system:
        final meta = message.metadata;
        if (meta != null && meta['type'] == 'ask_user') {
          return ChatAskUserCard(
            question: message.content,
            choices: (meta['choices'] as List?)?.cast<String>() ?? [],
            onChoice: onAskUserChoice,
          );
        }
        return ChatSystemBubble(content: message.content);
    }
  }
}
