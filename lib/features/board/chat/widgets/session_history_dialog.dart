import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/date_utils.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';

class SessionHistoryDialog extends StatefulWidget {
  const SessionHistoryDialog({required this.currentPanelId, this.onRestore});
  final String currentPanelId;
  final void Function(
    ChatSessionEntry entry,
    List<Map<String, dynamic>> messages,
  )?
  onRestore;

  @override
  State<SessionHistoryDialog> createState() => SessionHistoryDialogState();
}

class SessionHistoryDialogState extends State<SessionHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = ChatSessionHistory.instance.loadAll();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _entriesFuture = ChatSessionHistory.instance.loadAll();
    });
  }

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
            color:
                Theme.of(context).textTheme.bodyMedium?.color ??
                Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            'Session history',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 420,
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
                  style: TextStyle(
                    color:
                        context.appColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              );
            }
            return ListView.separated(
              itemCount: entries.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, index) {
                final e = entries[index];
                final isCurrent = e.id == widget.currentPanelId;
                return Container(
                  decoration: BoxDecoration(
                    color: isCurrent ? colors.surfaceElevated : colors.surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        isCurrent
                            ? Border.all(color: colors.statusActive, width: 0.5)
                            : null,
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
                                ? colors.statusActive
                                : context.appColors.textMuted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              e.sessionName.isNotEmpty
                                  ? e.sessionName
                                  : 'Unnamed session',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color:
                                    isCurrent
                                        ? colors.statusActive
                                        : Theme.of(
                                          context,
                                        ).colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${e.provider} • ${e.model} • ${e.messageCount} msgs',
                              style: TextStyle(
                                fontSize: 10,
                                color:
                                    context.appColors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatTimeAgo(e.lastMessageAt ?? e.createdAt),
                        style: TextStyle(
                          fontSize: 9,
                          color:
                              context.appColors.textMuted,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Restore button (not for current session)
                      if (!isCurrent && widget.onRestore != null)
                        _actionButton(
                          icon: Icons.restore,
                          color: colors.accentBlue,
                          tooltip: 'Restore',
                          onTap: () async {
                            final msgs = await ChatSessionHistory.instance
                                .loadMessages(e.id);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                            widget.onRestore?.call(e, msgs);
                          },
                        ),
                      // Delete button
                      _actionButton(
                        icon: Icons.delete_outline,
                        color: colors.statusError,
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

  Widget _actionButton({
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
