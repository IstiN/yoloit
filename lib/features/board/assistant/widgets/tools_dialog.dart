import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/cli_tools_picker_dialog.dart';

/// Thin wrapper around [CliToolsPickerDialog] for the assistant panel.
class ToolsDialog extends StatelessWidget {
  const ToolsDialog({
    super.key,
    required this.initialDisabled,
    required this.onPersist,
  });

  final Set<String> initialDisabled;
  final ValueChanged<Set<String>> onPersist;

  @override
  Widget build(BuildContext context) {
    return CliToolsPickerDialog(
      initialDisabled: initialDisabled,
      onPersist: onPersist,
      title: 'YoLo tools',
      description:
          'Checked tools are available to YoLo Chat. Unchecked tools are '
          'hidden from the local LLM and blocked at runtime.',
    );
  }
}
