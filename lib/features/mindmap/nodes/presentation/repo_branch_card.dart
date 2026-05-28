import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';

/// Presentation repo card — identical visuals to macOS RepoNode.
class RepoCard extends StatelessWidget {
  const RepoCard({super.key, required this.props});
  final RepoCardProps props;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      padding: EdgeInsets.zero,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.all(color: colors.accentBlue.withAlpha(89), width: 1.5),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: colors.accentBlue.withAlpha(15),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.account_tree_rounded,
                  size: 12,
                  color: colors.accentBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    props.repoName,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
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
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.all(color: colors.primary.withAlpha(102), width: 1.5),
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.primary.withAlpha(20),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(9),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.call_split, size: 11, color: colors.primaryLight),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    props.branch,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                      color: colors.primaryLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
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
