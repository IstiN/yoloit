import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';

/// Horizontal scrollable strip of changed-file chips.
class ChatChangedFilesStrip extends StatelessWidget {
  const ChatChangedFilesStrip({
    super.key,
    required this.files,
    required this.onOpenFile,
  });

  final List<String> files;
  final void Function(String path) onOpenFile;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final labelColor = context.appColors.textMuted.withAlpha(178);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.file_present_rounded, size: 13, color: colors.primary),
            const SizedBox(width: 5),
            Text(
              'Files changed',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children:
                files.map((path) {
                  final fileName = path.split('/').last;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Tooltip(
                      message: path,
                      waitDuration: const Duration(milliseconds: 350),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => onOpenFile(path),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: colors.border.withAlpha(153),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.description_outlined,
                                size: 12,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                fileName,
                                style: TextStyle(
                                  fontSize: 11,
                                  color:
                                      Theme.of(context).colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
          ),
        ),
      ],
    );
  }
}
