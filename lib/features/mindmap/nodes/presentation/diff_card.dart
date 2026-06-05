import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/ui/components/cards/mindmap_card_shell.dart';

/// Presentation diff card — renders changed files list + optional diff hunks.
class DiffCard extends StatelessWidget {
  const DiffCard({super.key, required this.props, this.onFileTap});
  final DiffCardProps props;
  final void Function(String filePath)? onFileTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final hasChanges = props.changedFiles.isNotEmpty || props.hunks.isNotEmpty;
    return MindmapCardShell(
      borderColor: colors.primary.withAlpha(112),
      headerIcon: Icons.compare_arrows_rounded,
      headerIconColor: colors.primary,
      headerTitle: props.repoName != null
          ? 'Diff · ${props.repoName}'
          : 'Git Changes · Diff',
      headerTrailing: [
        if (props.changedFiles.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: colors.primary.withAlpha(51),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '${props.changedFiles.length}',
              style: TextStyle(
                fontSize: 9,
                color: colors.primaryLight,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
      child:
          !hasChanges
              ? Center(
                child: Text(
                  'No changes',
                  style: TextStyle(
                    fontSize: 10,
                    color: colors.textMuted,
                  ),
                ),
              )
              : ListView(
                padding: const EdgeInsets.symmetric(vertical: 4),
                children: [
                  if (props.changedFiles.isNotEmpty) ...[
                    for (final f in props.changedFiles)
                      _ChangedFileRow(
                        file: f,
                        isSelected: props.selectedFilePath == f.path,
                        onTap:
                            onFileTap != null
                                ? () => onFileTap!(f.path)
                                : null,
                      ),
                    if (props.hunks.isNotEmpty)
                      Divider(color: colors.divider, height: 8),
                  ],
                  for (final h in props.hunks) _HunkWidget(hunk: h),
                ],
              ),
    );
  }
}

class _ChangedFileRow extends StatelessWidget {
  const _ChangedFileRow({
    required this.file,
    this.onTap,
    this.isSelected = false,
  });
  final ChangedFileEntry file;
  final VoidCallback? onTap;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final (color, label) = switch (file.status) {
      'added' => (colors.accentGreen, 'A'),
      'deleted' => (colors.accentRed, 'D'),
      'renamed' => (colors.accentOrange, 'R'),
      'untracked' => (colors.textSecondary, 'U'),
      _ => (colors.accentOrange, 'M'),
    };
    return InkWell(
      onTap: onTap,
      child: Container(
        color: isSelected ? colors.primary.withAlpha(26) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                file.name.isNotEmpty ? file.name : file.path.split('/').last,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? colors.textPrimary : colors.terminalText,
                  fontFamily: 'monospace',
                ),
              ),
            ),
            if (file.addedLines > 0)
              Text(
                '+${file.addedLines}',
                style: TextStyle(fontSize: 9, color: colors.accentGreen),
              ),
            if (file.removedLines > 0) ...[
              const SizedBox(width: 3),
              Text(
                '-${file.removedLines}',
                style: TextStyle(fontSize: 9, color: colors.accentRed),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HunkWidget extends StatelessWidget {
  const _HunkWidget({required this.hunk});
  final DiffHunk hunk;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: colors.diffContextBg,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Text(
            hunk.header,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              color: colors.textSecondary,
            ),
          ),
        ),
        for (final line in hunk.lines)
          Container(
            color: switch (line.type) {
              'add' => colors.diffAddBg,
              'remove' => colors.diffRemoveBg,
              _ => Colors.transparent,
            },
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
            child: Text(
              line.text,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10,
                color: switch (line.type) {
                  'add' => colors.diffAddText,
                  'remove' => colors.diffRemoveText,
                  _ => colors.terminalText,
                },
                height: 1.4,
              ),
              softWrap: false,
              overflow: TextOverflow.fade,
            ),
          ),
      ],
    );
  }
}
