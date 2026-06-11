import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/widgets/chat_running_tools_card.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';
import 'package:yoloit/features/board/chat/widgets/streaming_bubble.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/ui/components/chat/chat_message_molecule.dart';

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
          return const Padding(
            padding: EdgeInsets.only(top: 6, bottom: 2, right: 48, left: 12),
            child: ChatTypingIndicator(),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessage message) {
    return ChatMessageMolecule(
      message: message,
      activeToolCalls: activeToolCalls,
      subAgentPanels: subAgentPanels,
      isIgnoredToolCall: isIgnoredToolCall,
      isSubAgentToolCall: isSubAgentToolCall,
      onLinkTap: onLinkTap,
      onOpenFile: onOpenFile,
      onSendToPanel: onSendToPanel,
      onAskUserChoice: onAskUserChoice,
      onFocusPanel:
          (panelId) => context.read<BoardCubit>().focusPanel(panelId),
    );
  }
}
