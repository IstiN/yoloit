import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/panel_editor_dialog_mixin.dart';
import 'package:yoloit/ui/components/color_swatch_row.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';
import 'package:yoloit/ui/components/input/panel_text_controller_mixin.dart';
import 'package:yoloit/ui/components/typography/editor_section_label.dart';

class StickyNotePlugin extends BoardPanelPlugin with PanelEditorDialogMixin {
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
        parseHexColor(panel.state['color'] as String?) ??
        colors.accentOrange.withValues(alpha: 0.85);
    final textColor =
        parseHexColor(panel.state['textColor'] as String?) ??
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
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel) =>
      _StickyEditorDialog(panel: panel);
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

class _StickyNoteContentState extends State<_StickyNoteContent>
    with PanelTextControllerMixin<_StickyNoteContent> {
  @override
  String get panelText => widget.panel.state['text'] as String? ?? '';

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
          controller: controller,
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
            const EditorSectionLabel('Note color'),
            ColorSwatchRow(
              colors: _noteColors,
              selected: _color,
              onSelected: (value) => setState(() => _color = value),
            ),
            const SizedBox(height: 16),
            const EditorSectionLabel('Text color'),
            ColorSwatchRow(
              colors: _textColors,
              selected: _textColor,
              onSelected: (value) => setState(() => _textColor = value),
            ),
            const SizedBox(height: 16),
            EditorSectionLabel('Text size ${_fontSize.round()}'),
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
        EditorDialogActions(
          applyResultBuilder: () => {
            'color': _color,
            'textColor': _textColor,
            'fontSize': _fontSize,
          },
        ),
      ],
    );
  }
}

