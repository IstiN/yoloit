import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_attachment_preview.dart';
import 'package:yoloit/features/board/chat/widgets/chat_bubble_menu.dart';

class UserBubble extends StatefulWidget {
  const UserBubble({
    required this.content,
    this.attachments = const [],
    this.onOpenFile,
  });
  final String content;
  final List<String> attachments;
  final void Function(String path)? onOpenFile;

  @override
  State<UserBubble> createState() => UserBubbleState();
}

class UserBubbleState extends State<UserBubble> {
  bool _isHovered = false;

  static final _pathTokenRe = RegExp(r'^/\S+');

  static ({List<String> paths, String text}) _resolve(
    String content,
    List<String> attachments,
  ) {
    final tokens = content.split(RegExp(r'\s+'));
    final inlinePaths = tokens.where((t) => _pathTokenRe.hasMatch(t)).toList();
    final textOnly =
        tokens.where((t) => !_pathTokenRe.hasMatch(t)).join(' ').trim();

    final allPaths = <String>{...attachments, ...inlinePaths}.toList();
    return (paths: allPaths, text: textOnly);
  }

  @override
  Widget build(BuildContext context) {
    final resolved = _resolve(widget.content, widget.attachments);
    final hasText = resolved.text.isNotEmpty;
    final hasAttachments = resolved.paths.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2, left: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final availableWidth =
                  constraints.maxWidth.isFinite
                      ? constraints.maxWidth
                      : MediaQuery.sizeOf(context).width * 0.65;
              final bubbleMaxWidth =
                  availableWidth <= 38 ? availableWidth : availableWidth - 30;
              return Row(
                mainAxisSize: MainAxisSize.max,
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Visibility(
                    visible: _isHovered,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6, bottom: 4),
                      child: ChatBubbleMenu(
                        textToCopy: resolved.text,
                        light: false,
                      ),
                    ),
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: bubbleMaxWidth),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: context.appColors.surfaceElevated,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomLeft: Radius.circular(16),
                          bottomRight: Radius.circular(4),
                        ),
                        border: Border.all(
                          color: context.appColors.border.withAlpha(100),
                        ),
                      ),
                      child: RepaintBoundary(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasAttachments)
                              Padding(
                                padding: EdgeInsets.only(bottom: hasText ? 8 : 0),
                                child: ChatAttachmentPreview(
                                  paths: resolved.paths,
                                  onLight: false,
                                  onOpenFile: widget.onOpenFile,
                                ),
                              ),
                            if (hasText)
                              SelectionArea(
                                child: Text(
                                  resolved.text,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.appColors.textPrimary,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
