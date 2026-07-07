import 'package:flutter/material.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';

/// Shows an [AlertDialog] with a copyable [message] and a Copy button.
///
/// The dialog is 560 px wide, scrollable, and copies the message to the
/// clipboard when the Copy action is pressed.
Future<void> showCopyableErrorDialog({
  required BuildContext context,
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder:
        (dialogContext) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(child: SelectableText(message)),
          ),
          actions: [
            TextButton.icon(
              onPressed: () async {
                await copyToClipboard(message);
                if (!dialogContext.mounted) return;
                ScaffoldMessenger.of(dialogContext).showSnackBar(
                  const SnackBar(
                    content: Text('Copied error text'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
              icon: const Icon(Icons.copy_outlined, size: 18),
              label: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
  );
}
