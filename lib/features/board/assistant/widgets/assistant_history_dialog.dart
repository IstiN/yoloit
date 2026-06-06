import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_view.dart';
import 'package:yoloit/ui/components/buttons/action_icon_button.dart';

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
        child: SessionHistoryListView(
          future: _entriesFuture,
          currentPanelId: widget.currentSessionId ?? '',
          fallbackName: 'Yolo session',
          showModel: false,
          borderNonCurrent: true,
          activeColor: colors.accentGreen,
          mutedColor: colors.textSecondary,
          trailingActions: (entry, isCurrent) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isCurrent)
                ActionIconButton(
                  icon: Icons.restore,
                  color: colors.accentBlue,
                  tooltip: 'Restore',
                  onTap: () async {
                    final msgs = await ChatSessionHistory.instance
                        .loadMessages(entry.id);
                    if (!context.mounted) return;
                    Navigator.pop(context, msgs);
                  },
                ),
              ActionIconButton(
                icon: Icons.delete_outline,
                color: colors.accentRed,
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
