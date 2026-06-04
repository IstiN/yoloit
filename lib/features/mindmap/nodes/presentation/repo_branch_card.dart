import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/mindmap_card_shell.dart';

/// Presentation repo card — identical visuals to macOS RepoNode.
class RepoCard extends StatelessWidget {
  const RepoCard({super.key, required this.props});
  final RepoCardProps props;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MindmapCardShell(
      borderColor: colors.accentBlue.withAlpha(89),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MindmapCardHeader(
            icon: Icons.account_tree_rounded,
            iconColor: colors.accentBlue,
            title: props.repoName,
            backgroundColor: colors.accentBlue.withAlpha(15),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(Icons.call_split, size: 11, color: colors.accentBlue),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    props.branch,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      color: colors.accentBlue,
                    ),
                    overflow: TextOverflow.ellipsis,
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

/// Presentation branch card — identical visuals to macOS BranchNode.
class BranchCard extends StatelessWidget {
  const BranchCard({super.key, required this.props});
  final BranchCardProps props;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MindmapCardShell(
      borderColor: colors.primary.withAlpha(102),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          MindmapCardHeader(
            icon: Icons.call_split,
            iconColor: colors.primaryLight,
            iconSize: 11,
            gap: 5,
            title: props.branch,
            backgroundColor: colors.primary.withAlpha(20),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            titleStyle: TextStyle(
              fontSize: 10,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              color: colors.primaryLight,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  props.repoName,
                  style: TextStyle(fontSize: 10, color: colors.textSecondary),
                ),
                if (props.commitHash.isNotEmpty)
                  Text(
                    props.commitHash.length > 7
                        ? props.commitHash.substring(0, 7)
                        : props.commitHash,
                    style: TextStyle(
                      fontSize: 9,
                      fontFamily: 'monospace',
                      color: colors.textMuted,
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
