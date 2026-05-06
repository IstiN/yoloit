import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Built-in plugin that renders a Markdown note panel.
class MarkdownNotePlugin extends BoardPanelPlugin {
  const MarkdownNotePlugin();

  static const String kTypeId = 'board.note.markdown';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Markdown Note';

  @override
  IconData get icon => Icons.sticky_note_2_outlined;

  @override
  Color get accentColor => const Color(0xFFB46CFF);

  @override
  Size get defaultSize => const Size(360, 220);

  @override
  Map<String, dynamic> get initialState => {'markdown': ''};

  @override
  bool get hasEditor => true;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final markdown = panel.state['markdown'] as String? ?? '';
    return ClipRect(
      child: SingleChildScrollView(
        child: MarkdownBody(
          data: markdown.isEmpty ? '*Empty note*' : markdown,
        ),
      ),
    );
  }

  @override
  Future<bool> showEditor(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onSave,
  ) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => _MarkdownNoteEditorDialog(panel: panel),
    );
    if (result == null) return false;
    onSave(result);
    return true;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal editor dialog
// ─────────────────────────────────────────────────────────────────────────────

class _MarkdownNoteEditorDialog extends StatefulWidget {
  const _MarkdownNoteEditorDialog({required this.panel});

  final BoardPanelInstance panel;

  @override
  State<_MarkdownNoteEditorDialog> createState() =>
      _MarkdownNoteEditorDialogState();
}

class _MarkdownNoteEditorDialogState extends State<_MarkdownNoteEditorDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _mdCtrl;
  Color? _selectedColor;
  bool _isPreview = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.panel.title);
    _mdCtrl = TextEditingController(
      text: widget.panel.state['markdown'] as String? ?? '',
    );
    _selectedColor = widget.panel.color;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _mdCtrl.dispose();
    super.dispose();
  }

  void _wrapSelection(String before, String after, String placeholder) {
    final value = _mdCtrl.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final selected = start < end ? value.text.substring(start, end) : '';
    final replacement =
        '$before${selected.isEmpty ? placeholder : selected}$after';
    final updated = value.text.replaceRange(start, end, replacement);
    setState(() {
      _mdCtrl.value = value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
    });
  }

  void _prefixLines(String prefix) {
    final value = _mdCtrl.value;
    final selection =
        value.selection.isValid
            ? value.selection
            : TextSelection.collapsed(offset: value.text.length);
    final start = selection.start < selection.end
        ? selection.start
        : selection.end;
    final end = selection.start < selection.end
        ? selection.end
        : selection.start;
    final block = start < end ? value.text.substring(start, end) : '';
    final source = block.isEmpty ? 'item' : block;
    final replacement = source
        .split('\n')
        .map((line) => line.isEmpty ? prefix.trimRight() : '$prefix$line')
        .join('\n');
    final updated = value.text.replaceRange(start, end, replacement);
    setState(() {
      _mdCtrl.value = value.copyWith(
        text: updated,
        selection: TextSelection.collapsed(offset: start + replacement.length),
      );
    });
  }

  Future<void> _pickColor() async {
    Color picked = _selectedColor ?? const Color(0xFFB46CFF);
    await showDialog<void>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            title: const Text('Panel color'),
            content: ColorPicker(
              pickerColor: picked,
              onColorChanged: (c) => picked = c,
              enableAlpha: false,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  setState(() => _selectedColor = picked);
                  Navigator.of(ctx).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.panel.id.isEmpty
            ? 'Add markdown note'
            : 'Edit markdown note',
      ),
      content: SizedBox(
        width: 760,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _titleCtrl,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 12),
            // ── Toolbar ─────────────────────────────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ToolBtn(
                    icon: Icons.title,
                    tooltip: 'Heading',
                    onTap: () => _prefixLines('# '),
                  ),
                  _ToolBtn(
                    icon: Icons.format_bold,
                    tooltip: 'Bold',
                    onTap: () => _wrapSelection('**', '**', 'bold'),
                  ),
                  _ToolBtn(
                    icon: Icons.format_italic,
                    tooltip: 'Italic',
                    onTap: () => _wrapSelection('*', '*', 'italic'),
                  ),
                  _ToolBtn(
                    icon: Icons.format_list_bulleted,
                    tooltip: 'Bullet list',
                    onTap: () => _prefixLines('- '),
                  ),
                  _ToolBtn(
                    icon: Icons.check_box_outlined,
                    tooltip: 'Checklist',
                    onTap: () => _prefixLines('- [ ] '),
                  ),
                  _ToolBtn(
                    icon: Icons.link,
                    tooltip: 'Link',
                    onTap:
                        () =>
                            _wrapSelection('[', '](https://)', 'text'),
                  ),
                  _ToolBtn(
                    icon: Icons.code,
                    tooltip: 'Code block',
                    onTap:
                        () =>
                            _wrapSelection('```\n', '\n```', 'code'),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: _pickColor,
                    borderRadius: BorderRadius.circular(999),
                    child: Tooltip(
                      message: 'Panel color',
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              _selectedColor ??
                              const Color(0xFFB46CFF),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withAlpha(90),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.edit_outlined),
                        label: Text('Write'),
                      ),
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.preview_outlined),
                        label: Text('Preview'),
                      ),
                    ],
                    selected: {_isPreview},
                    onSelectionChanged: (sel) =>
                        setState(() => _isPreview = sel.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // ── Editor / Preview ────────────────────────────────────────────
            Container(
              height: 360,
              width: double.infinity,
              decoration: BoxDecoration(
                border: Border.all(color: Theme.of(context).dividerColor),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  _isPreview
                      ? SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: MarkdownBody(
                          data:
                              _mdCtrl.text.isEmpty
                                  ? '*Empty note*'
                                  : _mdCtrl.text,
                        ),
                      )
                      : TextField(
                        controller: _mdCtrl,
                        expands: true,
                        minLines: null,
                        maxLines: null,
                        textAlignVertical: TextAlignVertical.top,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.all(16),
                          hintText: 'Write your markdown note here…',
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop({
                '_title': _titleCtrl.text.trim(),
                '_color': _selectedColor?.toARGB32(),
                'markdown': _mdCtrl.text,
              }),
          child: Text(
            widget.panel.id.isEmpty ? 'Add' : 'Save',
          ),
        ),
      ],
    );
  }
}

class _ToolBtn extends StatelessWidget {
  const _ToolBtn({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      splashRadius: 16,
      visualDensity: VisualDensity.compact,
    );
  }
}
