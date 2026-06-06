import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_tile.dart';

class SessionHistoryListView extends StatelessWidget {
  const SessionHistoryListView({
    required this.future,
    required this.currentPanelId,
    this.trailingActions,
    this.onItemTap,
    this.fallbackName = 'Unnamed session',
    this.showModel = true,
    this.borderNonCurrent = false,
    this.activeColor,
    this.mutedColor,
    super.key,
  });

  final Future<List<ChatSessionEntry>> future;
  final String currentPanelId;
  final Widget Function(ChatSessionEntry entry, bool isCurrent)? trailingActions;
  final void Function(ChatSessionEntry entry)? onItemTap;
  final String fallbackName;
  final bool showModel;
  final bool borderNonCurrent;
  final Color? activeColor;
  final Color? mutedColor;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatSessionEntry>>(
      future: future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final entries = snapshot.data!;
        if (entries.isEmpty) {
          return Center(
            child: Text(
              'No sessions yet.\nStart chatting to see history here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor ?? context.appColors.textMuted,
                fontSize: 13,
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: entries.length,
          separatorBuilder: (_, _) => const SizedBox(height: 4),
          itemBuilder: (context, index) {
            final entry = entries[index];
            final isCurrent = entry.id == currentPanelId;
            return SessionHistoryListTile(
              entry: entry,
              isCurrent: isCurrent,
              onTap: onItemTap != null ? () => onItemTap!(entry) : null,
              trailing: trailingActions?.call(entry, isCurrent),
              fallbackName: fallbackName,
              showModel: showModel,
              borderNonCurrent: borderNonCurrent,
              activeColor: activeColor,
              mutedColor: mutedColor,
            );
          },
        );
      },
    );
  }
}
