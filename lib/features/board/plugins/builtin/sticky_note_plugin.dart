import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class StickyNotePlugin extends BoardPanelPlugin {
  const StickyNotePlugin();

  static const String kTypeId = 'board.sticky';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Sticky Note';

  @override
  IconData get icon => Icons.sticky_note_2_outlined;

  @override
  Color get accentColor => Colors.amber;

  @override
  Size get defaultSize => const Size(260, 220);

  @override
  Map<String, dynamic> get initialState => {
    'text': '',
    'color': '#FEF08A',
    'textColor': '#1F2937',
    'fontSize': 18.0,
  };

  @override
  bool get usePanelChrome => false;

  @override
  bool get showHeader => false;

  @override
  bool get hasEditor => true;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final colors = context.appColors;
    final color =
        _parseHex(panel.state['color'] as String?) ??
        colors.accentOrange.withValues(alpha: 0.85);
    final textColor =
        _parseHex(panel.state['textColor'] as String?) ??
        Theme.of(context).colorScheme.onSurface;
    final fontSize = (panel.state['fontSize'] as num?)?.toDouble() ?? 18.0;
    return _StickyNoteContent(
      panel: panel,
      color: color,
      textColor: textColor,
      fontSize: fontSize,
      onChanged: (value) {
        renderContext.onUpdateState({...panel.state, 'text': value});
      },
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
      builder: (ctx) => _StickyEditorDialog(panel: panel),
    );
    if (result == null) return false;
    onSave({...panel.state, ...result});
    return true;
  }
}

class _StickyNoteContent extends StatefulWidget {
  const _StickyNoteContent({
    required this.panel,
    required this.color,
    required this.textColor,
    required this.fontSize,
    required this.onChanged,
  });

  final BoardPanelInstance panel;
  final Color color;
  final Color textColor;
  final double fontSize;
  final ValueChanged<String> onChanged;

  @override
  State<_StickyNoteContent> createState() => _StickyNoteContentState();
}

class _StickyNoteContentState extends State<_StickyNoteContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textFromWidget());
  }

  @override
  void didUpdateWidget(covariant _StickyNoteContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextText = _textFromWidget();
    if (nextText != _controller.text) {
      _controller.value = _controller.value.copyWith(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
        composing: TextRange.empty,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _textFromWidget() => widget.panel.state['text'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.color,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.16),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: TextField(
          controller: _controller,
          expands: true,
          maxLines: null,
          minLines: null,
          keyboardType: TextInputType.multiline,
          textAlignVertical: TextAlignVertical.top,
          onChanged: widget.onChanged,
          decoration: InputDecoration(
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: 'Sticky note',
            hintStyle: TextStyle(
              color: widget.textColor.withValues(alpha: 0.55),
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w600,
            ),
            isCollapsed: true,
          ),
          cursorColor: widget.textColor,
          style: TextStyle(
            color: widget.textColor,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.w600,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _StickyEditorDialog extends StatefulWidget {
  const _StickyEditorDialog({required this.panel});

  final BoardPanelInstance panel;

  @override
  State<_StickyEditorDialog> createState() => _StickyEditorDialogState();
}

class _StickyEditorDialogState extends State<_StickyEditorDialog> {
  static const _noteColors = [
    '#FEF08A',
    '#FDE68A',
    '#FCA5A5',
    '#F9A8D4',
    '#C4B5FD',
    '#93C5FD',
    '#86EFAC',
    '#FFFFFF',
  ];
  static const _textColors = [
    '#111827',
    '#1F2937',
    '#FFFFFF',
    '#93C5FD',
    '#FBBF24',
    '#34D399',
    '#F472B6',
  ];

  late String _color;
  late String _textColor;
  late double _fontSize;

  @override
  void initState() {
    super.initState();
    _color = widget.panel.state['color'] as String? ?? '#FEF08A';
    _textColor = widget.panel.state['textColor'] as String? ?? '#1F2937';
    _fontSize = (widget.panel.state['fontSize'] as num?)?.toDouble() ?? 18.0;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sticky note settings'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SectionLabel('Note color'),
            _ColorRow(
              colors: _noteColors,
              selected: _color,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Text color'),
            _ColorRow(
              colors: _textColors,
              selected: _textColor,
              onSelected: (value) => setState(() => _textColor = value),
            ),
            const SizedBox(height: 16),
            _SectionLabel('Text size ${_fontSize.round()}'),
            Slider(
              min: 12,
              max: 36,
              divisions: 24,
              value: _fontSize,
              onChanged: (value) => setState(() => _fontSize = value),
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
                'color': _color,
                'textColor': _textColor,
                'fontSize': _fontSize,
              }),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

class _ColorRow extends StatelessWidget {
  const _ColorRow({
    required this.colors,
    required this.selected,
    required this.onSelected,
  });

  final List<String> colors;
  final String selected;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children:
          colors.map((hex) {
            final color = _parseHex(hex) ?? Colors.transparent;
            final isSelected = selected.toUpperCase() == hex.toUpperCase();
            return InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onSelected(hex),
              child: Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color:
                        isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                    width: isSelected ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
    );
  }
}

Color? _parseHex(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  final cleaned = raw.trim().replaceFirst('#', '');
  if (cleaned.length != 6 && cleaned.length != 8) return null;
  final value = int.tryParse(cleaned, radix: 16);
  if (value == null) return null;
  if (cleaned.length == 8) return Color(value);
  return Color.fromARGB(
    255,
    (value >> 16) & 255,
    (value >> 8) & 255,
    value & 255,
  );
}
