import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';
import 'package:yoloit/features/board/chat/widgets/streaming_bubble.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/ui/components/chat/chat_message_molecule.dart';
import 'package:yoloit/ui/components/layout/showcase_scaffold.dart';
import 'package:yoloit/ui/components/typography/typography.dart';

/// Debug showcase that renders every chat-message variant.
///
/// Uses [ChatMessageMolecule] with mock data so designers and developers can
/// preview and iterate on bubble styling without running a live chat session.
class ChatMessageShowcase extends StatelessWidget {
  const ChatMessageShowcase({super.key});

  static const _messages = <ChatMessage>[
    // 1. User text
    ChatMessage(
      id: 'msg-user-text',
      role: ChatRole.user,
      content: 'List all files in the current directory',
    ),

    // 2. User with attachment path
    ChatMessage(
      id: 'msg-user-attachment',
      role: ChatRole.user,
      content: 'Take a look at this screenshot',
      attachments: ['/Users/me/Desktop/screenshot.png'],
    ),

    // 3. Assistant plain text
    ChatMessage(
      id: 'msg-assistant-plain',
      role: ChatRole.assistant,
      content: 'Here is a list of files in your directory:\n\n'
          '- `pubspec.yaml`\n'
          '- `lib/main.dart`\n'
          '- `README.md`',
    ),

    // 4. Assistant with thinking blockquote
    ChatMessage(
      id: 'msg-assistant-thinking',
      role: ChatRole.assistant,
      content: '> **Thinking**\n'
          '> The user wants a list of files. I should use `ls`.\n\n'
          'Here is a list of files in your directory:\n\n'
          '- `pubspec.yaml`\n'
          '- `lib/main.dart`\n'
          '- `README.md`',
    ),

    // 5. Assistant with tool-call chips
    ChatMessage(
      id: 'msg-assistant-tools',
      role: ChatRole.assistant,
      content: 'Running the tools now…',
      toolCalls: [
        ChatToolCall(
          toolCallId: 'tc-1',
          toolName: 'Bash',
          arguments: {'command': 'ls -la'},
          isRunning: true,
        ),
        ChatToolCall(
          toolCallId: 'tc-2',
          toolName: 'ReadFile',
          arguments: {'path': 'pubspec.yaml'},
          isRunning: true,
        ),
      ],
    ),

    // 6. Assistant with token usage
    ChatMessage(
      id: 'msg-assistant-tokens',
      role: ChatRole.assistant,
      content: 'All done! Let me know if you need anything else.',
      tokenUsage: ChatTokenUsage(
        outputTokens: 142,
        premiumRequests: 1,
        totalApiDurationMs: 1200,
        sessionDurationMs: 3400,
        linesAdded: 0,
        linesRemoved: 0,
      ),
    ),

    // 7. Tool result — success
    ChatMessage(
      id: 'msg-tool-success',
      role: ChatRole.tool,
      content: 'total 128\n'
          'drwxr-xr-x  12 user  staff   384 Jun  9 12:00 .\n'
          'drwxr-xr-x   5 user  staff   160 Jun  9 11:55 ..\n'
          '-rw-r--r--   1 user  staff  2148 Jun  9 12:00 pubspec.yaml\n'
          '-rw-r--r--   1 user  staff  4821 Jun  9 12:00 README.md',
      toolName: 'Bash',
      toolCallId: 'tc-1',
      metadata: {'success': true},
    ),

    // 8. Tool result — error
    ChatMessage(
      id: 'msg-tool-error',
      role: ChatRole.tool,
      content: '<system>ERROR: command not found: invalid_cmd</system>',
      toolName: 'Bash',
      toolCallId: 'tc-3',
      metadata: {'success': false},
    ),

    // 9. System status
    ChatMessage(
      id: 'msg-system',
      role: ChatRole.system,
      content: 'Session resumed from checkpoint',
    ),

    // 10. Ask-user card
    ChatMessage(
      id: 'msg-ask-user',
      role: ChatRole.system,
      content: 'Do you want to apply these changes?',
      metadata: {
        'type': 'ask_user',
        'choices': ['Yes', 'No', 'Review diff'],
      },
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return ShowcaseScaffold(
      children: [
        const SectionTitle('Chat Message Variants'),
        const Caption(
          'All bubble types rendered via ChatMessageMolecule with mock data.',
        ),
        const SizedBox(height: 16),

        // ── Molecule variants ──
        for (final message in _messages)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ChatMessageMolecule(message: message),
          ),

        const Divider(height: 32),
        const SectionTitle('Ephemeral / Non-message Widgets'),
        const SizedBox(height: 8),

        // ── Streaming bubble ──
        const Caption('StreamingBubble'),
        const SizedBox(height: 4),
        const StreamingBubble(
          content: 'Thinking about the best approach to refactor this...',
          onLinkTap: null,
        ),
        const SizedBox(height: 16),

        // ── Typing indicator ──
        const Caption('ChatTypingIndicator'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(16),
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: const ChatTypingIndicator(),
          ),
        ),
      ],
    );
  }
}
