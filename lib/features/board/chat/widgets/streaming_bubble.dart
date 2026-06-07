import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_markdown_styles.dart';
import 'package:yoloit/features/board/chat/widgets/chat_typing_indicator.dart';

/// Streaming assistant response bubble with Markdown rendering.
class StreamingBubble extends StatelessWidget {
  const StreamingBubble({
    super.key,
    required this.content,
    this.onLinkTap,
  });

  final String content;
  final ValueChanged<String?>? onLinkTap;

  static final RegExp _brTagRe = RegExp(r'<br\s*/?>');

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final codeBg = colors.surface;
    final processedContent = content.replaceAll(_brTagRe, '\n');

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 48),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: chatBubbleDecoration(colors),
        child:
            processedContent.isEmpty
                ? const ChatTypingIndicator()
                : RepaintBoundary(
                  child: MarkdownBody(
                    data: processedContent,
                    onTapLink:
                        onLinkTap != null
                            ? (text, href, title) => onLinkTap!(href)
                            : null,
                    styleSheet: chatMarkdownStyle(
                      context: context,
                      colors: colors,
                      textColor: textColor,
                      codeBg: codeBg,
                    ),
                  ),
                ),
      ),
    );
  }
}
