import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/widgets/chat_image_thumbnail.dart';

/// Shows image thumbnails + file chips for a list of file paths.
/// Used in both user bubbles (attachments) and assistant bubbles (detected paths).
class ChatAttachmentPreview extends StatelessWidget {
  const ChatAttachmentPreview({
    super.key,
    required this.paths,
    this.onLight = true,
    this.onOpenFile,
  });

  final List<String> paths;

  /// True when rendered on a light background (assistant bubble), false on dark (user bubble).
  final bool onLight;

  /// Called when the user taps a file — uses board preview or system open.
  final void Function(String path)? onOpenFile;

  static final _imageRe = RegExp(
    r'\.(png|jpg|jpeg|gif|webp|bmp|svg)$',
    caseSensitive: false,
  );

  @override
  Widget build(BuildContext context) {
    final images = paths.where((p) => _imageRe.hasMatch(p)).toList();
    final files = paths.where((p) => !_imageRe.hasMatch(p)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (images.isNotEmpty) _buildImageGrid(context, images),
        if (images.isNotEmpty && files.isNotEmpty) const SizedBox(height: 6),
        if (files.isNotEmpty) _buildFileChips(context, files),
      ],
    );
  }

  Widget _buildImageGrid(BuildContext context, List<String> imagePaths) {
    if (imagePaths.length == 1) {
      return ChatImageThumbnail(
        path: imagePaths.first,
        maxWidth: 280,
        maxHeight: 200,
        onOpenFile: onOpenFile,
      );
    }
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children:
          imagePaths
              .map(
                (p) => ChatImageThumbnail(
                  path: p,
                  maxWidth: 140,
                  maxHeight: 120,
                  onOpenFile: onOpenFile,
                ),
              )
              .toList(),
    );
  }

  Widget _buildFileChips(BuildContext context, List<String> filePaths) {
    final colors = context.appColors;
    final chipBg =
        onLight
            ? Theme.of(context).colorScheme.surfaceContainerHighest
            : colors.textPrimary.withAlpha(38);
    final textColor =
        onLight ? Theme.of(context).colorScheme.onSurface : colors.textPrimary;
    final iconColor =
        onLight ? Theme.of(context).colorScheme.primary : colors.accentBlue;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      alignment: WrapAlignment.end,
      children:
          filePaths.map((p) {
            final name = p.split('/').last;
            return GestureDetector(
              onTap: () {
                if (onOpenFile != null) {
                  onOpenFile!(p);
                } else {
                  // Fallback: reveal in Finder
                  Process.run('open', ['-R', p]);
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color:
                        onLight
                            ? Theme.of(
                              context,
                            ).colorScheme.outline.withAlpha(76)
                            : colors.textPrimary.withAlpha(61),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.insert_drive_file_outlined,
                      size: 13,
                      color: iconColor,
                    ),
                    const SizedBox(width: 4),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 200),
                      child: Text(
                        name,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: textColor),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
    );
  }
}
