import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation files card — identical visuals to macOS FilesNode.
class FilesCard extends StatelessWidget {
  const FilesCard({super.key, required this.props, this.onFileSelect});
  final FilesCardProps props;
  final void Function(String path)? onFileSelect;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final visibleLimit = 8;
    final files = props.files.take(visibleLimit).toList();
    final remaining = props.files.length - visibleLimit;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.all(
          color: colors.textSecondary.withAlpha(89),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors.background.withAlpha(112),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
              border: Border(bottom: BorderSide(color: colors.divider)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.insert_drive_file_outlined,
                  size: 12,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'FILES CHANGED',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surfaceHighlight,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '${props.files.length}',
                    style: TextStyle(fontSize: 9, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                ...files.map(
                  (f) => _FileRow(
                    file: f,
                    onTap:
                        onFileSelect != null
                            ? () => onFileSelect!(f.path)
                            : null,
                  ),
                ),
                if (remaining > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: Text(
                      '+$remaining more',
                      style: TextStyle(fontSize: 9, color: colors.textMuted),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  const _FileRow({required this.file, this.onTap});
  final FileEntry file;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (statLabel, statBg, statFg) = switch (file.status.toLowerCase()) {
      'added' ||
      'a' => ('A', colors.accentGreen.withAlpha(38), colors.accentGreen),
      'deleted' ||
      'd' => ('D', colors.accentRed.withAlpha(38), colors.accentRed),
      'renamed' ||
      'r' => ('R', colors.accentBlue.withAlpha(38), colors.accentBlue),
      'untracked' ||
      '?' => ('?', colors.textSecondary.withAlpha(38), colors.textSecondary),
      _ => ('M', colors.accentOrange.withAlpha(38), colors.accentOrange),
    };

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          children: [
            Container(
              width: 14,
              height: 14,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: statBg,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                statLabel,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w800,
                  color: statFg,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                p.basename(file.path),
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.addedLines > 0 || file.removedLines > 0)
              Text(
                '+${file.addedLines}/-${file.removedLines}',
                style: TextStyle(
                  fontSize: 9,
                  color: colors.textMuted,
                  fontFamily: 'monospace',
                ),
              ),
          ],
        ),
      ),
    );
  }
}
