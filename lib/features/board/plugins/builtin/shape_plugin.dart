import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/common/shape_paths.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/panel_editor_dialog_mixin.dart';
import 'package:yoloit/ui/components/color_swatch_row.dart';
import 'package:yoloit/ui/components/dialog/editor_dialog_actions.dart';
import 'package:yoloit/ui/components/input/panel_text_controller_mixin.dart';
import 'package:yoloit/ui/components/typography/editor_section_label.dart';

double _readStateDouble(Object? value, double fallback) {
  if (value is num) return value.toDouble();
  if (value is String) {
    final parsed = num.tryParse(value.trim());
    if (parsed != null) return parsed.toDouble();
  }
  return fallback;
}

class ShapePlugin extends BoardPanelPlugin with PanelEditorDialogMixin {
  const ShapePlugin();

  static const String kTypeId = 'board.shape';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Shape / Frame';

  @override
  IconData get icon => Icons.category_outlined;

  @override
  Color get accentColor => Colors.lightBlueAccent;

  @override
  Size get defaultSize => const Size(300, 220);

  @override
  Map<String, dynamic> get initialState => {
    'shape': 'rectangle',
    'text': '',
    'fillColor': '#00000000',
    'strokeColor': '#93C5FD',
    'textColor': '#E2E8F0',
    'strokeWidth': 3.0,
    'fontSize': 18.0,
    'textHAlign': 'center',
    'textVAlign': 'center',
    'textOrientation': 'horizontal',
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
    final shape =
        (panel.state['shape'] as String? ?? 'rectangle').toLowerCase();
    final colors = context.appColors;
    final fillColor =
        parseHexColor(panel.state['fillColor'] as String?) ?? Colors.transparent;
    final strokeColor =
        parseHexColor(panel.state['strokeColor'] as String?) ?? colors.primaryLight;
    final textColor =
        parseHexColor(panel.state['textColor'] as String?) ?? colors.textPrimary;
    final strokeWidth = _readStateDouble(panel.state['strokeWidth'], 3.0);
    final fontSize = _readStateDouble(panel.state['fontSize'], 18.0);
    final textHAlign =
        (panel.state['textHAlign'] as String? ?? 'center').toLowerCase();
    final textVAlign =
        (panel.state['textVAlign'] as String? ?? 'center').toLowerCase();
    final textOrientation =
        (panel.state['textOrientation'] as String? ?? 'horizontal')
            .toLowerCase();

    return _ShapeContent(
      panel: panel,
      shape: shape,
      fillColor: fillColor,
      strokeColor: strokeColor,
      textColor: textColor,
      strokeWidth: strokeWidth,
      fontSize: fontSize,
      textHAlign: textHAlign,
      textVAlign: textVAlign,
      textOrientation: textOrientation,
      onChanged: (value) {
        renderContext.onUpdateState({...panel.state, 'text': value});
      },
    );
  }

  @override
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel) =>
      _ShapeEditorDialog(panel: panel);
}

class _ShapeContent extends StatefulWidget {
  const _ShapeContent({
    required this.panel,
    required this.shape,
    required this.fillColor,
    required this.strokeColor,
    required this.textColor,
    required this.strokeWidth,
    required this.fontSize,
    required this.textHAlign,
    required this.textVAlign,
    required this.textOrientation,
    required this.onChanged,
  });

  final BoardPanelInstance panel;
  final String shape;
  final Color fillColor;
  final Color strokeColor;
  final Color textColor;
  final double strokeWidth;
  final double fontSize;
  final String textHAlign;
  final String textVAlign;
  final String textOrientation;
  final ValueChanged<String> onChanged;

  @override
  State<_ShapeContent> createState() => _ShapeContentState();
}

class _ShapeContentState extends State<_ShapeContent>
    with PanelTextControllerMixin<_ShapeContent> {
  @override
  String get panelText => widget.panel.state['text'] as String? ?? '';

  @override
  Widget build(BuildContext context) {
    final alignment = _textAlignment(widget.textHAlign, widget.textVAlign);
    final textAlign = _textAlign(widget.textHAlign);
    final isVertical = widget.textOrientation == 'vertical';
    final editor = TextField(
      controller: controller,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlign: textAlign,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        hintText: 'Type',
        hintStyle: TextStyle(
          color: widget.textColor.withValues(alpha: 0.45),
          fontSize: widget.fontSize,
          fontWeight: FontWeight.w700,
        ),
        isCollapsed: true,
      ),
      cursorColor: widget.textColor,
      style: TextStyle(
        color: widget.textColor,
        fontSize: widget.fontSize,
        fontWeight: FontWeight.w700,
        height: 1.2,
      ),
    );
    return Stack(
      children: [
        CustomPaint(
          isComplex: true,
          painter: _ShapePainter(
            shape: widget.shape,
            fillColor: widget.fillColor,
            strokeColor: widget.strokeColor,
            strokeWidth: widget.strokeWidth,
          ),
          child: Align(
            alignment: alignment,
            child: Padding(
              padding: const EdgeInsets.all(26),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: isVertical ? 160 : 220,
                  maxHeight: isVertical ? 220 : 160,
                ),
                child:
                    isVertical
                        ? RotatedBox(quarterTurns: 3, child: editor)
                        : editor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ShapePalette extends StatelessWidget {
  const _ShapePalette({
    required this.selectedShape,
    required this.selectedColor,
    required this.textHAlign,
    required this.textVAlign,
    required this.textOrientation,
    required this.colors,
    required this.onUpdate,
  });

  final String selectedShape;
  final Color selectedColor;
  final String textHAlign;
  final String textVAlign;
  final String textOrientation;
  final AppColorScheme colors;
  final ValueChanged<Map<String, dynamic>> onUpdate;

  static const _options = [
    _ShapeOption('rectangle', 'Rect'),
    _ShapeOption('circle', 'Circle'),
    _ShapeOption('diamond', 'Diamond'),
    _ShapeOption('triangle', 'Triangle'),
    _ShapeOption('hexagon', 'Hex'),
    _ShapeOption('frame', 'Frame'),
  ];

  static const _colorOptions = [
    '#93C5FD',
    '#A78BFA',
    '#F472B6',
    '#FBBF24',
    '#34D399',
    '#F87171',
    '#E2E8F0',
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.divider),
        boxShadow: [
          BoxShadow(
            color: colors.background.withValues(alpha: 0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ..._options.map((option) {
              final selected = selectedShape == option.shape;
              return Tooltip(
                message: option.tooltip,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onUpdate({'shape': option.shape}),
                  child: Container(
                    width: 34,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color:
                          selected
                              ? colors.primary.withValues(alpha: 0.24)
                              : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      option.label,
                      style: TextStyle(
                        color:
                            selected
                                ? colors.primaryLight
                                : colors.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }),
            _ToolbarDivider(colors: colors),
            ..._colorOptions.map((hex) {
              final color = parseHexColor(hex)!;
              final selected = _sameColor(selectedColor, color);
              return Tooltip(
                message: 'Color $hex',
                child: InkWell(
                  borderRadius: BorderRadius.circular(999),
                  onTap: () => onUpdate({'strokeColor': hex, 'textColor': hex}),
                  child: Container(
                    width: 24,
                    height: 24,
                    margin: const EdgeInsets.symmetric(horizontal: 1),
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? colors.primaryLight : colors.divider,
                        width: selected ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              );
            }),
            _ToolbarDivider(colors: colors),
            _TextToolButton(
              label: 'L',
              tooltip: 'Text left',
              selected: textHAlign == 'left',
              colors: colors,
              onTap: () => onUpdate({'textHAlign': 'left'}),
            ),
            _TextToolButton(
              label: 'C',
              tooltip: 'Text center',
              selected: textHAlign == 'center',
              colors: colors,
              onTap: () => onUpdate({'textHAlign': 'center'}),
            ),
            _TextToolButton(
              label: 'R',
              tooltip: 'Text right',
              selected: textHAlign == 'right',
              colors: colors,
              onTap: () => onUpdate({'textHAlign': 'right'}),
            ),
            _TextToolButton(
              label: 'T',
              tooltip: 'Text top',
              selected: textVAlign == 'top',
              colors: colors,
              onTap: () => onUpdate({'textVAlign': 'top'}),
            ),
            _TextToolButton(
              label: 'M',
              tooltip: 'Text middle',
              selected: textVAlign == 'center',
              colors: colors,
              onTap: () => onUpdate({'textVAlign': 'center'}),
            ),
            _TextToolButton(
              label: 'B',
              tooltip: 'Text bottom',
              selected: textVAlign == 'bottom',
              colors: colors,
              onTap: () => onUpdate({'textVAlign': 'bottom'}),
            ),
            _TextToolButton(
              label: 'H',
              tooltip: 'Horizontal text',
              selected: textOrientation == 'horizontal',
              colors: colors,
              onTap: () => onUpdate({'textOrientation': 'horizontal'}),
            ),
            _TextToolButton(
              label: 'V',
              tooltip: 'Vertical text',
              selected: textOrientation == 'vertical',
              colors: colors,
              onTap: () => onUpdate({'textOrientation': 'vertical'}),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToolbarDivider extends StatelessWidget {
  const _ToolbarDivider({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 3),
      color: colors.divider,
    );
  }
}

class _TextToolButton extends StatelessWidget {
  const _TextToolButton({
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  final String label;
  final String tooltip;
  final bool selected;
  final AppColorScheme colors;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          width: 26,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color:
                selected
                    ? colors.primary.withValues(alpha: 0.24)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.primaryLight : colors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }
}

class _ShapeOption {
  const _ShapeOption(this.shape, this.tooltip);

  final String shape;
  final String tooltip;

  String get label => switch (shape) {
    'rectangle' => '▭',
    'circle' => '○',
    'diamond' => '◇',
    'triangle' => '△',
    'hexagon' => '⬡',
    'frame' => '▢',
    _ => '?',
  };
}

class _ShapeEditorDialog extends StatefulWidget {
  const _ShapeEditorDialog({required this.panel});

  final BoardPanelInstance panel;

  @override
  State<_ShapeEditorDialog> createState() => _ShapeEditorDialogState();
}

class _ShapeEditorDialogState extends State<_ShapeEditorDialog> {
  late String _shape;
  late String _fillColor;
  late String _strokeColor;
  late String _textColor;
  late String _text;
  late double _strokeWidth;
  late double _fontSize;
  late String _textHAlign;
  late String _textVAlign;
  late String _textOrientation;
  late final TextEditingController _textController;

  static const _colors = [
    '#00000000',
    '#93C5FD',
    '#A78BFA',
    '#F472B6',
    '#FBBF24',
    '#34D399',
    '#F87171',
    '#E2E8F0',
  ];

  @override
  void initState() {
    super.initState();
    final state = widget.panel.state;
    _shape = state['shape'] as String? ?? 'rectangle';
    _fillColor = state['fillColor'] as String? ?? '#00000000';
    _strokeColor = state['strokeColor'] as String? ?? '#93C5FD';
    _textColor = state['textColor'] as String? ?? '#E2E8F0';
    _text = state['text'] as String? ?? '';
    _textController = TextEditingController(text: _text);
    _strokeWidth = _readStateDouble(state['strokeWidth'], 3.0);
    _fontSize = _readStateDouble(state['fontSize'], 18.0);
    _textHAlign = state['textHAlign'] as String? ?? 'center';
    _textVAlign = state['textVAlign'] as String? ?? 'center';
    _textOrientation = state['textOrientation'] as String? ?? 'horizontal';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Shape settings'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const EditorSectionLabel('Shape'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    _ShapePalette._options.map((option) {
                      final selected = _shape == option.shape;
                      return ChoiceChip(
                        label: Text(option.tooltip),
                        selected: selected,
                        onSelected:
                            (_) => setState(() => _shape = option.shape),
                      );
                    }).toList(),
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Stroke color'),
              ColorSwatchRow(
                colors: _colors.where((hex) => hex != '#00000000').toList(),
                selected: _strokeColor,
                onSelected: (value) => setState(() => _strokeColor = value),
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Fill color'),
              ColorSwatchRow(
                colors: _colors,
                selected: _fillColor,
                onSelected: (value) => setState(() => _fillColor = value),
                transparentIcon: const Icon(Icons.block, size: 16),
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Text color'),
              ColorSwatchRow(
                colors: _colors.where((hex) => hex != '#00000000').toList(),
                selected: _textColor,
                onSelected: (value) => setState(() => _textColor = value),
              ),
              const SizedBox(height: 18),
              EditorSectionLabel('Stroke width ${_strokeWidth.round()}'),
              Slider(
                min: 1,
                max: 12,
                divisions: 11,
                value: _strokeWidth.clamp(1, 12),
                onChanged: (value) => setState(() => _strokeWidth = value),
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Text alignment'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _choice('Left', _textHAlign == 'left', () {
                    setState(() => _textHAlign = 'left');
                  }),
                  _choice('Center', _textHAlign == 'center', () {
                    setState(() => _textHAlign = 'center');
                  }),
                  _choice('Right', _textHAlign == 'right', () {
                    setState(() => _textHAlign = 'right');
                  }),
                  _choice('Top', _textVAlign == 'top', () {
                    setState(() => _textVAlign = 'top');
                  }),
                  _choice('Middle', _textVAlign == 'center', () {
                    setState(() => _textVAlign = 'center');
                  }),
                  _choice('Bottom', _textVAlign == 'bottom', () {
                    setState(() => _textVAlign = 'bottom');
                  }),
                ],
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Text orientation'),
              Wrap(
                spacing: 8,
                children: [
                  _choice('Horizontal', _textOrientation == 'horizontal', () {
                    setState(() => _textOrientation = 'horizontal');
                  }),
                  _choice('Vertical', _textOrientation == 'vertical', () {
                    setState(() => _textOrientation = 'vertical');
                  }),
                ],
              ),
              const SizedBox(height: 18),
              const EditorSectionLabel('Text'),
              TextField(
                minLines: 1,
                maxLines: 4,
                controller: _textController,
                onChanged: (value) => _text = value,
                decoration: const InputDecoration(
                  hintText: 'Type custom text',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 18),
              EditorSectionLabel('Text size ${_fontSize.round()}'),
              Slider(
                min: 12,
                max: 36,
                divisions: 24,
                value: _fontSize.clamp(12, 36),
                onChanged: (value) => setState(() => _fontSize = value),
              ),
            ],
          ),
        ),
      ),
      actions: [
        EditorDialogActions(
          applyResultBuilder: () => {
            'shape': _shape,
            'fillColor': _fillColor,
            'strokeColor': _strokeColor,
            'textColor': _textColor,
            'text': _text,
            'strokeWidth': _strokeWidth,
            'fontSize': _fontSize,
            'textHAlign': _textHAlign,
            'textVAlign': _textVAlign,
            'textOrientation': _textOrientation,
          },
        ),
      ],
    );
  }

  Widget _choice(String label, bool selected, VoidCallback onSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}

Alignment _textAlignment(String hAlign, String vAlign) {
  final x = switch (hAlign) {
    'left' => -1.0,
    'right' => 1.0,
    _ => 0.0,
  };
  final y = switch (vAlign) {
    'top' => -1.0,
    'bottom' => 1.0,
    _ => 0.0,
  };
  return Alignment(x, y);
}

TextAlign _textAlign(String hAlign) {
  return switch (hAlign) {
    'left' => TextAlign.left,
    'right' => TextAlign.right,
    _ => TextAlign.center,
  };
}

bool _sameColor(Color a, Color b) {
  return (a.a * 255).round() == (b.a * 255).round() &&
      (a.r * 255).round() == (b.r * 255).round() &&
      (a.g * 255).round() == (b.g * 255).round() &&
      (a.b * 255).round() == (b.b * 255).round();
}

/// Test-only seam for [_sameColor] — its only call site lives in the
/// (currently uninstantiated) [_ShapePalette], so expose it for unit tests.
@visibleForTesting
bool shapeColorsEqual(Color a, Color b) => _sameColor(a, b);

class _ShapePainter extends CustomPainter {
  const _ShapePainter({
    required this.shape,
    required this.fillColor,
    required this.strokeColor,
    required this.strokeWidth,
  });

  final String shape;
  final Color fillColor;
  final Color strokeColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final inset = strokeWidth / 2 + 6;
    final shapeRect = rect.deflate(inset);
    final fill =
        Paint()
          ..color = shape == 'frame' ? Colors.transparent : fillColor
          ..style = PaintingStyle.fill;
    final stroke =
        Paint()
          ..color = strokeColor
          ..strokeWidth = strokeWidth
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round;

    final path = switch (shape) {
      'circle' || 'oval' => Path()..addOval(shapeRect),
      'diamond' => diamondPath(shapeRect),
      'triangle' => trianglePath(shapeRect),
      'hexagon' => _polygon(shapeRect, 6),
      'frame' =>
        Path()..addRRect(
          RRect.fromRectAndRadius(shapeRect, const Radius.circular(10)),
        ),
      _ =>
        Path()..addRRect(
          RRect.fromRectAndRadius(shapeRect, const Radius.circular(14)),
        ),
    };

    canvas.drawPath(path, fill);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(covariant _ShapePainter oldDelegate) {
    return oldDelegate.shape != shape ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}



Path _polygon(Rect rect, int sides) {
  final path = Path();
  final center = rect.center;
  final radius = math.min(rect.width, rect.height) / 2;
  for (var i = 0; i < sides; i++) {
    final angle = -math.pi / 2 + (math.pi * 2 * i / sides);
    final point = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    if (i == 0) {
      path.moveTo(point.dx, point.dy);
    } else {
      path.lineTo(point.dx, point.dy);
    }
  }
  return path..close();
}

/// Test-only factory for exercising [_ShapePalette], which is otherwise never
/// instantiated because the editor dialog builds [ChoiceChip]s directly.
@visibleForTesting
Widget createShapePaletteForTest({
  required String selectedShape,
  required Color selectedColor,
  required String textHAlign,
  required String textVAlign,
  required String textOrientation,
  required AppColorScheme colors,
  required ValueChanged<Map<String, dynamic>> onUpdate,
}) =>
    _ShapePalette(
      selectedShape: selectedShape,
      selectedColor: selectedColor,
      textHAlign: textHAlign,
      textVAlign: textVAlign,
      textOrientation: textOrientation,
      colors: colors,
      onUpdate: onUpdate,
    );

