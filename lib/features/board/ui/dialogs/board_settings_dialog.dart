import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';

/// Dialog for editing board name and default folder.
class BoardSettingsDialog extends StatefulWidget {
  const BoardSettingsDialog({
    super.key,
    required this.initialName,
    required this.initialDefaultFolder,
    required this.remoteInfo,
    this.initialArchived = false,
    this.onPickFolder,
  });

  final String initialName;
  final String initialDefaultFolder;
  final bool initialArchived;
  final ({String url, String? token, String boardId, int? revision})?
      remoteInfo;

  /// Optional folder picker callback. When null, the folder picker row is
  /// hidden (e.g. on the web, where board state lives in browser storage).
  final AsyncValueGetter<String?>? onPickFolder;

  @override
  State<BoardSettingsDialog> createState() => _BoardSettingsDialogState();
}

class _BoardSettingsDialogState extends State<BoardSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;
  late bool _archived;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _folderController = TextEditingController(
      text: widget.initialDefaultFolder,
    );
    _archived = widget.initialArchived;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isWeb = PlatformCapabilities.current.platform == RuntimePlatform.web;
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
              decoration: InputDecoration(
                labelText: 'Default folder',
                helperText:
                    isWeb
                        ? 'Not used in the browser; board state is kept in web storage.'
                        : 'Used for new chats, terminals, and file trees.',
              ),
            ),
            if (!isWeb && widget.onPickFolder != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await widget.onPickFolder!();
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
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Archived'),
              subtitle: const Text(
                'Archived boards are hidden from the overview and previews.',
              ),
              value: _archived,
              onChanged: (value) => setState(() => _archived = value),
            ),
          ],
        ),
      ),
      actions: [
        EditorDialogActions(
          applyResultBuilder: () => (
            name: _nameController.text.trim(),
            defaultFolder: _folderController.text.trim(),
            archived: _archived,
          ),
          applyLabel: 'Save',
        ),
      ],
    );
  }
}
