import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
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
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(4),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(16),
            bottomRight: Radius.circular(16),
          ),
        ),
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
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        fontSize: 13,
                        color: textColor,
                        height: 1.5,
                      ),
                      a: TextStyle(
                        fontSize: 13,
                        color: colors.primary,
                        decoration: TextDecoration.underline,
                      ),
                      code: TextStyle(
                        fontSize: 11.5,
                        color: colors.terminalPrompt,
                        backgroundColor: codeBg,
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: codeBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.border),
                      ),
                    ),
                  ),
                ),
      ),
    );
  }
}
