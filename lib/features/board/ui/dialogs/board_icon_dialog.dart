import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_icon_resolver.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/board/ui/board_icon.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';

/// Result of [showBoardIconDialog]: [icon] is `null` when the user picked
/// "auto-detect" (reset), otherwise it is the chosen override.
typedef BoardIconDialogResult = ({BoardIconSpec? icon});

/// Shows the board icon picker and returns the selected icon, or `null` when
/// the dialog was cancelled.
Future<BoardIconDialogResult?> showBoardIconDialog(
  BuildContext context, {
  required BoardDocument board,
}) {
  return showAdaptiveYoloDialog<BoardIconDialogResult>(
    context: context,
    builder: (_) => BoardIconDialog(board: board),
  );
}

/// Curated emoji choices for the emoji picker grid.
const List<String> kBoardEmojiChoices = [
  '🚀', '✨', '🔥', '💡', '⭐', '🎯', '🏆', '💎',
  '⚡', '🌟', '🎨', '🎬', '🎮', '🎵', '📈', '📊',
  '🧠', '🤖', '👾', '💻', '⌨️', '🖥️', '📱', '⌚',
  '🔧', '🛠️', '⚙️', '🧩', '🔬', '🧪', '📐', '📏',
  '📦', '🗂️', '📁', '📝', '📌', '📎', '🔍', '🔎',
  '🔒', '🔑', '🛡️', '☁️', '🌐', '🔗', '📡', '🛰️',
  '🐛', '🐞', '🦄', '🐳', '🦀', '🐹', '🦊', '🐼',
  '🌈', '🍀', '🌸', '🍕', '☕', '🍺', '🎂', '🏖️',
  '✅', '❌', '⚠️', '💥', '❤️', '💜', '💙', '💚',
];

/// Dialog for choosing a board icon: images found in the board's default
/// folder, bundled presets, an emoji, a picked image file, or auto-detection.
class BoardIconDialog extends StatefulWidget {
  const BoardIconDialog({super.key, required this.board});

  final BoardDocument board;

  @override
  State<BoardIconDialog> createState() => _BoardIconDialogState();
}

class _BoardIconDialogState extends State<BoardIconDialog> {
  late BoardIconSpec? _selected = widget.board.icon;
  bool _emojiPickerVisible = false;
  final TextEditingController _emojiController = TextEditingController();
  late final List<String> _folderCandidates = _loadFolderCandidates();

  @override
  void dispose() {
    _emojiController.dispose();
    super.dispose();
  }

  List<String> _loadFolderCandidates() {
    if (kIsWeb) return const [];
    final folder = widget.board.defaultFolder;
    if (folder.isEmpty) return const [];
    return BoardIconResolver.instance.findIconCandidates(folder);
  }

  /// Synthetic board used to render previews of the prospective icon.
  BoardDocument get _previewBoard => BoardDocument(
    id: widget.board.id,
    name: widget.board.name,
    metadata: {
      'defaultFolder': widget.board.defaultFolder,
      if (_selected != null) 'icon': _selected!.toJson(),
    },
  );

  Future<void> _pickImageFile() async {
    final selection = await BoardFilePicker.pickFile(
      context,
      initialPath:
          widget.board.defaultFolder.isEmpty ? null : widget.board.defaultFolder,
      title: 'Choose board icon image',
    );
    if (!mounted || selection == null) return;
    setState(() {
      _selected = BoardIconSpec(
        kind: BoardIconSpec.kindFile,
        value: selection.path,
      );
      _emojiPickerVisible = false;
    });
  }

  void _applyEmoji(String raw) {
    final emoji = raw.trim();
    if (emoji.isEmpty) return;
    setState(() {
      _selected = BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: emoji);
    });
  }

  void _select(BoardIconSpec spec) {
    setState(() {
      _selected = spec;
      _emojiPickerVisible = spec.kind == BoardIconSpec.kindEmoji;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AdaptiveDialogScaffold(
      title: 'Board icon',
      icon: const Icon(Icons.image_outlined),
      maxWidth: 480,
      body: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildPreviewRow(colors),
            if (_folderCandidates.isNotEmpty) ...[
              const SizedBox(height: 20),
              _buildFolderCandidatesSection(colors),
            ],
            const SizedBox(height: 20),
            _buildPresetsSection(colors),
            const SizedBox(height: 20),
            _buildActionButtons(),
            if (_emojiPickerVisible) ...[
              const SizedBox(height: 12),
              _buildEmojiPicker(colors),
            ],
            const SizedBox(height: 8),
            Text(
              _selected == null
                  ? 'Auto-detect looks for an app icon inside the board\'s '
                      'default folder (e.g. a Flutter app icon) and falls back '
                      'to a generated letter avatar.'
                  : 'Tip: pick "Auto-detect" to derive the icon from the '
                      'board\'s default folder again.',
              style: TextStyle(
                color: colors.textMuted.withAlpha(180),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
      actions: [
        EditorDialogActions(
          applyLabel: 'Save',
          applyResultBuilder: () => (icon: _selected),
        ),
      ],
    );
  }

  Widget _buildPreviewRow(AppColorScheme colors) {
    return Row(
      children: [
        BoardIcon(board: _previewBoard, size: 56),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.board.name,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _describeSelection(),
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(AppColorScheme colors, String label) {
    return Text(
      label,
      style: TextStyle(
        color: colors.textMuted,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildFolderCandidatesSection(AppColorScheme colors) {
    final folderName = p.basename(widget.board.defaultFolder);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel(colors, 'Found in $folderName'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final path in _folderCandidates)
              _IconTile(
                key: Key('board-icon-candidate-$path'),
                tooltip: p.basename(path),
                selected:
                    _selected?.kind == BoardIconSpec.kindFile &&
                    _selected?.value == path,
                spec: BoardIconSpec(kind: BoardIconSpec.kindFile, value: path),
                seedId: 'candidate-$path',
                onTap:
                    () => _select(
                      BoardIconSpec(kind: BoardIconSpec.kindFile, value: path),
                    ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildPresetsSection(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionLabel(colors, 'Presets'),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final preset in kBoardIconPresets.values)
              _IconTile(
                tooltip: preset.label,
                selected:
                    _selected?.kind == BoardIconSpec.kindBuiltin &&
                    _selected?.value == preset.key,
                spec: BoardIconSpec(
                  kind: BoardIconSpec.kindBuiltin,
                  value: preset.key,
                ),
                seedId: 'preset-${preset.key}',
                onTap:
                    () => _select(
                      BoardIconSpec(
                        kind: BoardIconSpec.kindBuiltin,
                        value: preset.key,
                      ),
                    ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!kIsWeb)
          OutlinedButton.icon(
            onPressed: _pickImageFile,
            icon: const Icon(Icons.file_open_outlined, size: 18),
            label: const Text('Choose image…'),
          ),
        OutlinedButton.icon(
          key: const Key('board-icon-emoji-toggle'),
          onPressed:
              () => setState(() {
                _emojiPickerVisible = !_emojiPickerVisible;
              }),
          icon: const Icon(Icons.emoji_emotions_outlined, size: 18),
          label: const Text('Emoji…'),
        ),
        OutlinedButton.icon(
          onPressed:
              () => setState(() {
                _selected = null;
                _emojiPickerVisible = false;
              }),
          icon: const Icon(Icons.auto_fix_high, size: 18),
          label: const Text('Auto-detect'),
        ),
      ],
    );
  }

  Widget _buildEmojiPicker(AppColorScheme colors) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _emojiController,
          maxLength: 4,
          decoration: const InputDecoration(
            labelText: 'Emoji',
            hintText: '🚀',
            counterText: '',
          ),
          onChanged: _applyEmoji,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            for (final emoji in kBoardEmojiChoices)
              _EmojiTile(
                emoji: emoji,
                selected:
                    _selected?.kind == BoardIconSpec.kindEmoji &&
                    _selected?.value == emoji,
                onTap:
                    () => _select(
                      BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: emoji),
                    ),
              ),
          ],
        ),
      ],
    );
  }

  String _describeSelection() {
    final selected = _selected;
    if (selected == null) {
      return 'Auto-detect from default folder';
    }
    return switch (selected.kind) {
      BoardIconSpec.kindEmoji => 'Emoji ${selected.value}',
      BoardIconSpec.kindBuiltin =>
        'Preset: ${kBoardIconPresets[selected.value]?.label ?? selected.value}',
      _ => 'Image: ${selected.value}',
    };
  }
}

/// A selectable 48px icon tile used for folder candidates and presets.
class _IconTile extends StatelessWidget {
  const _IconTile({
    super.key,
    required this.tooltip,
    required this.selected,
    required this.spec,
    required this.seedId,
    required this.onTap,
  });

  final String tooltip;
  final bool selected;
  final BoardIconSpec spec;
  final String seedId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final previewBoard = BoardDocument(
      id: seedId,
      name: tooltip,
      metadata: {'icon': spec.toJson()},
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 48,
          height: 48,
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  selected ? colors.textPrimary.withAlpha(160) : colors.border,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: BoardIcon(board: previewBoard, size: 36),
        ),
      ),
    );
  }
}

class _EmojiTile extends StatelessWidget {
  const _EmojiTile({
    required this.emoji,
    required this.selected,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color:
              selected
                  ? colors.surfaceHighlight
                  : colors.surfaceElevated.withAlpha(120),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color:
                selected ? colors.textPrimary.withAlpha(160) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(emoji, style: const TextStyle(fontSize: 18, height: 1)),
      ),
    );
  }
}
