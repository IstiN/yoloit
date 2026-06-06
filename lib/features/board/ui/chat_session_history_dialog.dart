import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history/session_history_list_view.dart';
import 'package:yoloit/ui/components/buttons/action_icon_button.dart';

class ChatSessionHistoryDialog extends StatefulWidget {
  const ChatSessionHistoryDialog({required this.panelId});
  final String panelId;

  @override
  State<ChatSessionHistoryDialog> createState() =>
      ChatSessionHistoryDialogState();
}

class ChatSessionHistoryDialogState extends State<ChatSessionHistoryDialog> {
  late Future<List<ChatSessionEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = ChatSessionHistory.instance.loadAll();
  }

  void refresh() {
    setState(() {
      _entriesFuture = ChatSessionHistory.instance.loadAll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final secondaryColor =
        Theme.of(context).textTheme.bodyMedium?.color ??
        Theme.of(context).colorScheme.onSurface;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return AlertDialog(
      backgroundColor: colors.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.history, size: 18, color: secondaryColor),
          const SizedBox(width: 8),
          Text(
            'Session history',
            style: TextStyle(color: onSurface, fontSize: 16),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        height: 420,
        child: SessionHistoryListView(
          future: _entriesFuture,
          currentPanelId: widget.panelId,
          onItemTap: (entry) async {
            final msgs = await ChatSessionHistory.instance.loadMessages(entry.id);
            if (!context.mounted) return;
            Navigator.pop(context);
            final cubit = context.read<BoardCubit>();
            await cubit.createChatPanel(
              title:
                  entry.sessionName.isNotEmpty
                      ? entry.sessionName
                      : 'Restored chat',
              sessionName: entry.sessionName,
              workingDir: entry.workingDir,
              model: entry.model,
              envGroupIds: entry.envGroupIds,
              messages: msgs,
            );
          },
          trailingActions: (entry, isCurrent) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isCurrent)
                ActionIconButton(
                  icon: Icons.restore,
                  color: colors.accentBlue,
                  tooltip: 'Restore as new chat',
                  onTap: () async {
                    final msgs = await ChatSessionHistory.instance
                        .loadMessages(entry.id);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                    final cubit = context.read<BoardCubit>();
                    await cubit.createChatPanel(
                      title:
                          entry.sessionName.isNotEmpty
                              ? entry.sessionName
                              : 'Restored chat',
                      sessionName: entry.sessionName,
                      workingDir: entry.workingDir,
                      model: entry.model,
                      envGroupIds: entry.envGroupIds,
                      messages: msgs,
                    );
                  },
                ),
              ActionIconButton(
                icon: Icons.delete_outline,
                color: colors.statusError,
                tooltip: 'Delete',
                onTap: () async {
                  await ChatSessionHistory.instance.delete(entry.id);
                  refresh();
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
