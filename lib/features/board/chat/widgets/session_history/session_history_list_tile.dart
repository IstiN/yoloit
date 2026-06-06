import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/date_utils.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';

class SessionHistoryListTile extends StatelessWidget {
  const SessionHistoryListTile({
    required this.entry,
    required this.isCurrent,
    this.onTap,
    this.trailing,
    super.key,
  });

  final ChatSessionEntry entry;
  final bool isCurrent;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = colors.textMuted;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final tile = Container(
      decoration: BoxDecoration(
        color: isCurrent ? colors.surfaceElevated : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: isCurrent
            ? Border.all(color: colors.statusActive, width: 0.5)
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 14,
            color: isCurrent ? colors.statusActive : mutedColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.sessionName.isNotEmpty
                      ? entry.sessionName
                      : 'Unnamed session',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isCurrent ? colors.statusActive : onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.provider} • ${entry.model} • ${entry.messageCount} msgs',
                  style: TextStyle(
                    fontSize: 10,
                    color: mutedColor,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatTimeAgo(entry.lastMessageAt ?? entry.createdAt),
            style: TextStyle(
              fontSize: 9,
              color: mutedColor,
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 6),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap == null) {
      return tile;
    }

    return GestureDetector(
      onTap: isCurrent ? null : onTap,
      child: tile,
    );
  }
}
