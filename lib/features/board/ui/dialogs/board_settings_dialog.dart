import 'package:flutter/material.dart';

import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';

/// Dialog for editing board name and default folder.
class BoardSettingsDialog extends StatefulWidget {
  const BoardSettingsDialog({
    super.key,
    required this.initialName,
    required this.initialDefaultFolder,
    required this.remoteInfo,
  });

  final String initialName;
  final String initialDefaultFolder;
  final ({String url, String? token, String boardId, int? revision})?
      remoteInfo;

  @override
  State<BoardSettingsDialog> createState() => _BoardSettingsDialogState();
}

class _BoardSettingsDialogState extends State<BoardSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _folderController = TextEditingController(
      text: widget.initialDefaultFolder,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdaptiveDialogScaffold(
      title: 'Board settings',
      icon: const Icon(Icons.settings_outlined),
      maxWidth: 520,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Board name'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _folderController,
              decoration: const InputDecoration(
                labelText: 'Default folder',
                helperText: 'Used for new chats, terminals, and file trees.',
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final selected = await BoardFilePicker.pickDirectory(
                      context,
                      remoteInfo: widget.remoteInfo,
                      initialPath: _folderController.text,
                      title:
                          widget.remoteInfo == null
                              ? 'Choose folder'
                              : 'Choose remote folder',
                    );
                    if (!mounted || selected == null) return;
                    _folderController.text = selected;
                  },
                  icon: Icon(
                    widget.remoteInfo == null
                        ? Icons.folder_open_outlined
                        : Icons.cloud_queue,
                  ),
                  label: Text(
                    widget.remoteInfo == null
                        ? 'Choose folder'
                        : 'Choose remote folder',
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () => _folderController.clear(),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        EditorDialogActions(
          applyResultBuilder: () => (
            name: _nameController.text.trim(),
            defaultFolder: _folderController.text.trim(),
          ),
          applyLabel: 'Save',
        ),
      ],
    );
  }
}
