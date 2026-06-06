import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_view.dart';
import 'package:yoloit/ui/components/buttons/action_icon_button.dart';

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
        child: SessionHistoryListView(
          future: _entriesFuture,
          currentPanelId: widget.currentPanelId,
          trailingActions: (entry, isCurrent) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isCurrent && widget.onRestore != null)
                ActionIconButton(
                  icon: Icons.restore,
                  color: colors.accentBlue,
                  tooltip: 'Restore',
                  onTap: () async {
                    final msgs = await ChatSessionHistory.instance
                        .loadMessages(entry.id);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    widget.onRestore?.call(entry, msgs);
                  },
                ),
              ActionIconButton(
                icon: Icons.delete_outline,
                color: colors.statusError,
                tooltip: 'Delete',
                onTap: () async {
                  await ChatSessionHistory.instance.delete(entry.id);
                  _refresh();
                },
              ),
            ],
          ),
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
}
