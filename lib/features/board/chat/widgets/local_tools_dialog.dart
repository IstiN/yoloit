import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/widgets/cli_tools_picker_dialog.dart';

/// Thin wrapper around [CliToolsPickerDialog] for the chat panel.
class LocalToolsDialog extends StatelessWidget {
  const LocalToolsDialog({
    super.key,
    required this.disabledToolNames,
    required this.enabledCount,
    required this.onChanged,
  });

  final Set<String> disabledToolNames;
  final int enabledCount;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    return CliToolsPickerDialog(
      initialDisabled: disabledToolNames,
      onPersist: onChanged,
      title: 'YoLo Chat tools',
      description:
          'Checked tools are exposed to the local LLM. Unchecked tools are '
          'removed from the tool schema and blocked if the model still tries '
          'to call them.',
      showDisableAll: false,
      enabledCount: enabledCount,
    );
  }
}
