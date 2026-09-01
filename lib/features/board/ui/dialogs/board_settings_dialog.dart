import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_icon.dart';
import 'package:yoloit/features/board/ui/dialogs/board_icon_dialog.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';

/// Dialog for editing board name and default folder.
class BoardSettingsDialog extends StatefulWidget {
  const BoardSettingsDialog({
    super.key,
    required this.initialName,
    required this.initialDefaultFolder,
    required this.remoteInfo,
    this.initialArchived = false,
    this.initialIcon,
    this.boardId = 'board-settings-preview',
    this.onPickFolder,
  });

  final String initialName;
  final String initialDefaultFolder;
  final bool initialArchived;

  /// Current board icon override; `null` means auto-detect.
  final BoardIconSpec? initialIcon;

  /// Board id, used as the stable seed for the fallback avatar preview.
  final String boardId;
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
  late BoardIconSpec? _icon;
  bool _iconChanged = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _folderController = TextEditingController(
      text: widget.initialDefaultFolder,
    );
    _archived = widget.initialArchived;
    _icon = widget.initialIcon;
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
            _buildIconRow(context),
            const SizedBox(height: 8),
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
            icon: _icon,
            iconChanged: _iconChanged,
          ),
          applyLabel: 'Save',
        ),
      ],
    );
  }

  Widget _buildIconRow(BuildContext context) {
    final colors = context.appColors;
    final previewBoard = BoardDocument(
      id: widget.boardId,
      name: _nameController.text.trim(),
      metadata: {
        'defaultFolder': _folderController.text.trim(),
        if (_icon != null) 'icon': _icon!.toJson(),
      },
    );
    return Row(
      children: [
        BoardIcon(board: previewBoard, size: 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Board icon',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _icon == null
                    ? 'Auto-detected from the default folder.'
                    : 'Custom: ${_icon!.describe()}',
                style: TextStyle(color: colors.textMuted, fontSize: 11),
              ),
            ],
          ),
        ),
        TextButton.icon(
          key: const Key('board-settings-change-icon'),
          onPressed: () => _changeIcon(context),
          icon: const Icon(Icons.image_outlined, size: 16),
          label: const Text('Change…'),
        ),
      ],
    );
  }

  Future<void> _changeIcon(BuildContext context) async {
    final previewBoard = BoardDocument(
      id: widget.boardId,
      name: _nameController.text.trim(),
      metadata: {
        'defaultFolder': _folderController.text.trim(),
        if (_icon != null) 'icon': _icon!.toJson(),
      },
    );
    final result = await showBoardIconDialog(context, board: previewBoard);
    if (!mounted || result == null) return;
    setState(() {
      _icon = result.icon;
      _iconChanged = true;
    });
  }
}
