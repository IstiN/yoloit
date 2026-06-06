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
    this.fallbackName = 'Unnamed session',
    this.showModel = true,
    this.borderNonCurrent = false,
    this.activeColor,
    this.mutedColor,
    super.key,
  });

  final ChatSessionEntry entry;
  final bool isCurrent;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String fallbackName;
  final bool showModel;
  final bool borderNonCurrent;
  final Color? activeColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final muted = mutedColor ?? colors.textMuted;
    final active = activeColor ?? colors.statusActive;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final subtitle = showModel
        ? '${entry.provider} • ${entry.model} • ${entry.messageCount} msgs'
        : '${entry.provider} • ${entry.messageCount} msgs';

    final tile = Container(
      decoration: BoxDecoration(
        color: isCurrent ? colors.surfaceElevated : colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: isCurrent
            ? Border.all(color: active, width: 0.5)
            : borderNonCurrent
                ? Border.all(color: colors.border.withAlpha(80), width: 0.5)
                : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 14,
            color: isCurrent ? active : muted,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.sessionName.isNotEmpty
                      ? entry.sessionName
                      : fallbackName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isCurrent ? active : onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: muted,
                  ),
                ),
              ],
            ),
          ),
          Text(
            formatTimeAgo(entry.lastMessageAt ?? entry.createdAt),
            style: TextStyle(
              fontSize: 9,
              color: muted,
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
