import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/date_utils.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Yolo Assistant — Session history dialog
// ─────────────────────────────────────────────────────────────────────────────

class AssistantHistoryDialog extends StatefulWidget {
  const AssistantHistoryDialog({super.key, this.currentSessionId});
  final String? currentSessionId;

  @override
  State<AssistantHistoryDialog> createState() =>
      AssistantHistoryDialogState();
}

class AssistantHistoryDialogState extends State<AssistantHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadYoloSessions();
  }

  Future<List<ChatSessionEntry>> _loadYoloSessions() async {
    final all = await ChatSessionHistory.instance.loadAll();
    // Show only sessions created by the yolo assistant (id starts with 'yolo-').
    return all.where((e) => e.id.startsWith('yolo-')).toList();
  }

  void _refresh() => setState(() => _entriesFuture = _loadYoloSessions());

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Yolo session history',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        height: 440,
        child: FutureBuilder<List<ChatSessionEntry>>(
          future: _entriesFuture,
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
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, index) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isCurrent = e.id == widget.currentSessionId;
                return Container(
                  decoration: BoxDecoration(
                    color: isCurrent ? colors.surfaceElevated : colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCurrent
                            ? Border.all(color: colors.accentGreen, width: 0.5)
                            : Border.all(
                              color: colors.border.withAlpha(80),
                              width: 0.5,
                            ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 14,
                        color:
                            isCurrent
                                ? colors.accentGreen
                                : colors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.sessionName.isNotEmpty
                                  ? e.sessionName
                                  : 'Yolo session',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color:
                                    isCurrent
                                        ? colors.accentGreen
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.provider} • ${e.messageCount} msgs',
                              style: TextStyle(
                                fontSize: 10,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatTimeAgo(e.lastMessageAt ?? e.createdAt),
                        style: TextStyle(
                          fontSize: 9,
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Restore
                      if (!isCurrent)
                        _historyBtn(
                          icon: Icons.restore,
                          color: colors.accentBlue,
                          tooltip: 'Restore',
                          onTap: () async {
                            final msgs = await ChatSessionHistory.instance
                                .loadMessages(e.id);
                            if (!context.mounted) return;
                            Navigator.pop(context, msgs);
                          },
                        ),
                      // Delete
                      _historyBtn(
                        icon: Icons.delete_outline,
                        color: colors.accentRed,
                        tooltip: 'Delete',
                        onTap: () async {
                          await ChatSessionHistory.instance.delete(e.id);
                          _refresh();
                        },
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _historyBtn({
    required IconData icon,
    required Color color,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: color),
        ),
      ),
    );
  }

}
