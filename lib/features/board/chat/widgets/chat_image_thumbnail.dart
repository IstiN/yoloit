import 'dart:io';

import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Displays a local image file as a thumbnail with tap-to-open.
class ChatImageThumbnail extends StatelessWidget {
  const ChatImageThumbnail({
    super.key,
    required this.path,
    this.maxWidth = 280,
    this.maxHeight = 200,
    this.onOpenFile,
  });

  final String path;
  final double maxWidth;
  final double maxHeight;
  final void Function(String path)? onOpenFile;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final name = path.split('/').last;

    return GestureDetector(
      onTap: () {
        if (onOpenFile != null) {
          onOpenFile!(path);
        } else {
          Process.run('open', [path]);
        }
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth,
                maxHeight: maxHeight,
              ),
              child: Image.file(
                file,
                fit: BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder:
                    (_, __, ___) => Container(
                      width: 80,
                      height: 60,
                      decoration: BoxDecoration(
                        color: context.appColors.background.withAlpha(31),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.broken_image_outlined,
                        size: 24,
                        color: context.appColors.textPrimary.withAlpha(97),
                      ),
                    ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            name,
            style: TextStyle(fontSize: 9, color: context.appColors.accentBlue),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
