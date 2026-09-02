import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_icon.dart';
import 'package:yoloit/features/board/ui/dialogs/board_icon_dialog.dart';
import 'package:yoloit/features/settings/ui/env_group_selection_field.dart';
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
    this.initialEnvGroupIds = const <String>[],
    this.initialEnv = const <String, String>{},
    this.boardId = 'board-settings-preview',
    this.onPickFolder,
  });

  final String initialName;
  final String initialDefaultFolder;
  final bool initialArchived;

  /// Board-level default env groups injected into every new terminal.
  final List<String> initialEnvGroupIds;

  /// Board-level inline env variables injected into every new terminal.
  final Map<String, String> initialEnv;

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

class _EnvRow {
  final keyController = TextEditingController();
  final valueController = TextEditingController();

  void dispose() {
    keyController.dispose();
    valueController.dispose();
  }
}

class _BoardSettingsDialogState extends State<BoardSettingsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _folderController;
  late bool _archived;
  late BoardIconSpec? _icon;
  bool _iconChanged = false;
  late List<String> _envGroupIds;
  final List<_EnvRow> _envRows = [];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _folderController = TextEditingController(
      text: widget.initialDefaultFolder,
    );
    _archived = widget.initialArchived;
    _icon = widget.initialIcon;
    _envGroupIds = List<String>.from(widget.initialEnvGroupIds);
    for (final entry in widget.initialEnv.entries) {
      _envRows.add(
        _EnvRow()
          ..keyController.text = entry.key
          ..valueController.text = entry.value,
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _folderController.dispose();
    for (final row in _envRows) {
      row.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectEnv() => {
    for (final row in _envRows)
      if (row.keyController.text.trim().isNotEmpty)
        row.keyController.text.trim(): row.valueController.text,
  };

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
            const Divider(height: 24),
            _buildDefaultEnvSection(context),
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
            envGroupIds: _envGroupIds,
            env: _collectEnv(),
          ),
          applyLabel: 'Save',
        ),
      ],
    );
  }

  Widget _buildDefaultEnvSection(BuildContext context) {
    final colors = context.appColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Default env variables',
          style: TextStyle(
            color: colors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Injected into every new terminal on this board. '
          'Terminal-specific env groups are added on top.',
          style: TextStyle(color: colors.textMuted, fontSize: 11),
        ),
        const SizedBox(height: 10),
        EnvGroupSelectionField(
          selectedGroupIds: _envGroupIds,
          onChanged: (selected) => setState(() => _envGroupIds = selected),
          label: 'Env groups',
        ),
        const SizedBox(height: 10),
        ..._envRows.indexed.map(
          (entry) {
            final rowIndex = entry.$1;
            final row = entry.$2;
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: row.keyController,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'KEY',
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: row.valueController,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'VALUE',
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() {
                      _envRows.removeAt(rowIndex).dispose();
                    }),
                    icon: const Icon(Icons.delete_outline, size: 16),
                    color: colors.accentRed,
                    splashRadius: 14,
                  ),
                ],
              ),
            );
          },
        ),
        TextButton.icon(
          onPressed: () => setState(() => _envRows.add(_EnvRow())),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Add Variable'),
          style: TextButton.styleFrom(foregroundColor: colors.primary),
        ),
      ],
    );
  }

  BoardDocument get _previewBoard => BoardDocument(
    id: widget.boardId,
    name: _nameController.text.trim(),
    metadata: {
      'defaultFolder': _folderController.text.trim(),
      if (_icon != null) 'icon': _icon!.toJson(),
    },
  );

  Widget _buildIconRow(BuildContext context) {
    final colors = context.appColors;
    return Row(
      children: [
        BoardIcon(board: _previewBoard, size: 36),
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
    final result = await showBoardIconDialog(context, board: _previewBoard);
    if (!mounted || result == null) return;
    setState(() {
      _icon = result.icon;
      _iconChanged = true;
    });
  }
}
