import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_attachment_preview.dart';
import 'package:yoloit/features/board/chat/widgets/chat_bubble_menu.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class AssistantBubble extends StatefulWidget {
  const AssistantBubble({
    required this.content,
    this.toolCalls = const [],
    this.tokenUsage,
    this.onLinkTap,
    this.onOpenFile,
  });
  final String content;
  final List<ChatToolCall> toolCalls;
  final ChatTokenUsage? tokenUsage;
  final void Function(String? href)? onLinkTap;
  final void Function(String path)? onOpenFile;

  @override
  State<AssistantBubble> createState() => AssistantBubbleState();
}

class AssistantBubbleState extends State<AssistantBubble> {
  bool _isHovered = false;

  static final _absPathRe = RegExp(
    r'(?<![`\w])(/[\w./\-_ ]+\.[\w]{1,10})(?![`\w])',
  );

  static List<String> _extractFilePaths(String text) {
    final matches = _absPathRe.allMatches(text);
    final seen = <String>{};
    final result = <String>[];
    for (final m in matches) {
      final path = m.group(1)!.trim();
      if (seen.add(path)) result.add(path);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final textColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final mutedColor =
        context.appColors.textMuted.withAlpha(153);
    final codeBg = colors.surface;
    final processedContent = widget.content.replaceAll(
      RegExp(r'<br\s*/?>'),
      '\n',
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, right: 16),
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.toolCalls.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children:
                      widget.toolCalls
                          .map(
                            (tc) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: colors.accentOrange.withAlpha(21),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: colors.accentOrange.withAlpha(48),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.terminal_rounded,
                                    size: 10,
                                    color: colors.accentOrange,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    tc.toolName,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: colors.accentOrange,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                          .toList(),
                ),
              ),

            if (processedContent.trim().isNotEmpty)
              LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth =
                      constraints.maxWidth.isFinite
                          ? constraints.maxWidth
                          : MediaQuery.sizeOf(context).width * 0.65;
                  final bubbleMaxWidth =
                      availableWidth <= 158
                          ? availableWidth
                          : availableWidth - 38;
                  return Row(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
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
                          child: SelectionArea(
                            child: MarkdownBody(
                              data: processedContent,
                              selectable: false,
                              onTapLink: (text, href, title) {
                                if (widget.onLinkTap != null) {
                                  widget.onLinkTap!(href);
                                } else if (href != null && href.isNotEmpty) {
                                  PlatformLauncher.instance.openUrl(href);
                                }
                              },
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
                              ),
                            ),
                          ),
                        ),
                      ),
                      Visibility(
                        visible: _isHovered,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6, bottom: 4),
                          child: ChatBubbleMenu(
                            textToCopy: processedContent,
                            light: false,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),

            if (widget.tokenUsage != null)
              Padding(
                padding: const EdgeInsets.only(top: 3, left: 6),
                child: Text(
                  '${widget.tokenUsage!.outputTokens} tok',
                  style: TextStyle(
                    fontSize: 9,
                    color:
                        context.appColors.textMuted,
                  ),
                ),
              ),

            Builder(
              builder: (_) {
                final detectedPaths = _extractFilePaths(widget.content);
                if (detectedPaths.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: ChatAttachmentPreview(
                    paths: detectedPaths,
                    onLight: true,
                    onOpenFile: widget.onOpenFile,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
