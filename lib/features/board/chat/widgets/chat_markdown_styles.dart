import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';

final _chatBrTagRe = RegExp(r'<br\s*/?>');

/// Prepares chat bubble content by replacing `<br>` tags and returning
/// the commonly needed colors.
(String processedContent, AppColorScheme colors, Color textColor, Color codeBg)
prepareChatBubble(BuildContext context, String content) {
  final colors = context.appColors;
  final textColor =
      Theme.of(context).textTheme.bodyMedium?.color ??
      Theme.of(context).colorScheme.onSurface;
  final codeBg = colors.surface;
  final processedContent = content.replaceAll(_chatBrTagRe, '\n');
  return (processedContent, colors, textColor, codeBg);
}

/// Shared bubble decoration used by both [AssistantBubble] and [StreamingBubble].
BoxDecoration chatBubbleDecoration(AppColorScheme colors) => BoxDecoration(
  color: colors.surfaceElevated,
  borderRadius: const BorderRadius.only(
    topLeft: Radius.circular(4),
    topRight: Radius.circular(16),
    bottomLeft: Radius.circular(16),
    bottomRight: Radius.circular(16),
  ),
);

/// Shared Markdown style sheet for chat bubbles.
MarkdownStyleSheet chatMarkdownStyle({
  required BuildContext context,
  required AppColorScheme colors,
  required Color textColor,
  required Color codeBg,
}) {
  final mutedColor = colors.textMuted.withAlpha(153);
  return MarkdownStyleSheet(
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
      fontFamily: 'JetBrains Mono',
      color: colors.terminalPrompt,
      backgroundColor: codeBg,
    ),
    codeblockDecoration: BoxDecoration(
      color: codeBg,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: colors.border),
    ),
    codeblockPadding: const EdgeInsets.all(10),
    listBullet: TextStyle(
      fontSize: 13,
      color: mutedColor,
    ),
    h1: TextStyle(
      fontSize: 16,
      color: textColor,
      fontWeight: FontWeight.w600,
    ),
    h2: TextStyle(
      fontSize: 14,
      color: textColor,
      fontWeight: FontWeight.w600,
    ),
    h3: TextStyle(
      fontSize: 13,
      color: textColor,
      fontWeight: FontWeight.w500,
    ),
    blockquote: TextStyle(
      fontSize: 12,
      color: mutedColor,
      fontStyle: FontStyle.italic,
      height: 1.4,
    ),
    blockquoteDecoration: BoxDecoration(
      color: colors.surfaceHighlight.withAlpha(80),
      borderRadius: BorderRadius.circular(6),
      border: Border(
        left: BorderSide(color: colors.primary.withAlpha(120), width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  );
}
