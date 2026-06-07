import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_view.dart';
import 'package:yoloit/ui/components/buttons/action_icon_button.dart';

/// Shared session-history dialog used by both the assistant panel
/// ([AssistantHistoryDialog]) and the chat panel ([SessionHistoryDialog]).
class SessionHistoryPickerDialog extends StatefulWidget {
  const SessionHistoryPickerDialog({
    super.key,
    required this.title,
    required this.currentPanelId,
    this.filter,
    this.showModel = true,
    this.borderNonCurrent = false,
    this.activeColor,
    this.mutedColor,
    this.deleteColor,
    this.restoreColor,
    this.width = 380,
    this.height = 420,
    this.onRestore,
  });

  final String title;
  final String currentPanelId;

  /// Optional filter applied to loaded entries.
  final bool Function(ChatSessionEntry)? filter;

  final bool showModel;
  final bool borderNonCurrent;
  final Color? activeColor;
  final Color? mutedColor;
  final Color? deleteColor;
  final Color? restoreColor;
  final double width;
  final double height;

  /// When provided, restore is enabled and yields `(entry, messages)`.
  final void Function(ChatSessionEntry, List<Map<String, dynamic>>)? onRestore;

  @override
  State<SessionHistoryPickerDialog> createState() =>
      _SessionHistoryPickerDialogState();
}

class _SessionHistoryPickerDialogState
    extends State<SessionHistoryPickerDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = _loadEntries();
  }

  Future<List<ChatSessionEntry>> _loadEntries() async {
    var all = await ChatSessionHistory.instance.loadAll();
    if (widget.filter != null) {
      all = all.where(widget.filter!).toList();
    }
    return all;
  }

  void _refresh() {
    if (!mounted) return;
    setState(() => _entriesFuture = _loadEntries());
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
            color: Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 8),
          Text(
            widget.title,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 16,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: widget.width,
        height: widget.height,
        child: SessionHistoryListView(
          future: _entriesFuture,
          currentPanelId: widget.currentPanelId,
          fallbackName: widget.title.contains('Yolo') ? 'Yolo session' : 'Session',
          showModel: widget.showModel,
          borderNonCurrent: widget.borderNonCurrent,
          activeColor: widget.activeColor ?? colors.accentGreen,
          mutedColor: widget.mutedColor ?? colors.textSecondary,
          trailingActions: (entry, isCurrent) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isCurrent)
                ActionIconButton(
                  icon: Icons.restore,
                  color: widget.restoreColor ?? colors.accentBlue,
                  tooltip: 'Restore',
                  onTap: () async {
                    final msgs = await ChatSessionHistory.instance
                        .loadMessages(entry.id);
                    if (!context.mounted) return;
                    if (widget.onRestore != null) {
                      Navigator.pop(context);
                      widget.onRestore!(entry, msgs);
                    } else {
                      Navigator.pop(context, msgs);
                    }
                  },
                ),
              ActionIconButton(
                icon: Icons.delete_outline,
                color: widget.deleteColor ?? colors.statusError,
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
