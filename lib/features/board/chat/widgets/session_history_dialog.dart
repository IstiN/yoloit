import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/widgets/session_history_picker_dialog.dart';

/// Thin wrapper around [SessionHistoryPickerDialog] for the chat panel.
class SessionHistoryDialog extends StatelessWidget {
  const SessionHistoryDialog({
    required this.currentPanelId,
    this.onRestore,
  });

  final String currentPanelId;
  final void Function(
    ChatSessionEntry entry,
    List<Map<String, dynamic>> messages,
  )?
  onRestore;

  @override
  Widget build(BuildContext context) {
    return SessionHistoryPickerDialog(
      title: 'Session history',
      currentPanelId: currentPanelId,
      onRestore: onRestore,
    );
  }
}
