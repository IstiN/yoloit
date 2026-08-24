import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/chat_markdown_styles.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';
import 'package:yoloit/features/board/chat/widgets/incremental_markdown_body.dart';

/// Streaming assistant response bubble with Markdown rendering.
class StreamingBubble extends StatelessWidget {
  const StreamingBubble({
    super.key,
    required this.content,
    this.onLinkTap,
  });

  final String content;
  final ValueChanged<String?>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final (processedContent, colors, textColor, codeBg) =
        prepareChatBubble(context, content);

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child:
            processedContent.isEmpty
                ? const ChatTypingIndicator()
                : RepaintBoundary(
                  child: IncrementalMarkdownBody(
                    data: processedContent,
                    colors: colors,
                    textColor: textColor,
                    codeBg: codeBg,
                    onTapLink:
                        onLinkTap != null
                            ? (text, href, title) => onLinkTap!(href)
                            : null,
                  ),
                ),
      ),
    );
  }
}
