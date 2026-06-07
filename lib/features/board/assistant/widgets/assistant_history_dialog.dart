import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/session_history_picker_dialog.dart';

/// Thin wrapper around [SessionHistoryPickerDialog] for the assistant panel.
class AssistantHistoryDialog extends StatelessWidget {
  const AssistantHistoryDialog({super.key, this.currentSessionId});

  final String? currentSessionId;

  @override
  Widget build(BuildContext context) {
    return SessionHistoryPickerDialog(
      title: 'Yolo session history',
      currentPanelId: currentSessionId ?? '',
      filter: (e) => e.id.startsWith('yolo-'),
      showModel: false,
      borderNonCurrent: true,
      width: 400,
      height: 440,
    );
  }
}
