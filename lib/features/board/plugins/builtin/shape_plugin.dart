import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

class ShapePlugin extends BoardPanelPlugin {
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
  };

  @override
  bool get usePanelChrome => false;

  @override
  bool get showHeader => false;

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
        _parseHex(panel.state['fillColor'] as String?) ?? Colors.transparent;
    final strokeColor =
        _parseHex(panel.state['strokeColor'] as String?) ?? colors.primaryLight;
    final textColor =
        _parseHex(panel.state['textColor'] as String?) ?? colors.textPrimary;
    final strokeWidth = (panel.state['strokeWidth'] as num?)?.toDouble() ?? 3.0;

    return _ShapeContent(
      panel: panel,
      shape: shape,
      fillColor: fillColor,
      strokeColor: strokeColor,
      textColor: textColor,
      strokeWidth: strokeWidth,
      onChanged: (value) {
        renderContext.onUpdateState({...panel.state, 'text': value});
      },
    );
  }
}

class _ShapeContent extends StatefulWidget {
  const _ShapeContent({
    required this.panel,
    required this.shape,
    required this.fillColor,
    required this.strokeColor,
    required this.textColor,
    required this.strokeWidth,
    required this.onChanged,
  });

  final BoardPanelInstance panel;
  final String shape;
  final Color fillColor;
  final Color strokeColor;
  final Color textColor;
  final double strokeWidth;
  final ValueChanged<String> onChanged;

  @override
  State<_ShapeContent> createState() => _ShapeContentState();
}

class _ShapeContentState extends State<_ShapeContent> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _textFromWidget());
  }

  @override
  void didUpdateWidget(covariant _ShapeContent oldWidget) {
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
    return CustomPaint(
      painter: _ShapePainter(
        shape: widget.shape,
        fillColor: widget.fillColor,
        strokeColor: widget.strokeColor,
        strokeWidth: widget.strokeWidth,
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: TextField(
            controller: _controller,
            maxLines: null,
            keyboardType: TextInputType.multiline,
            textAlign: TextAlign.center,
            onChanged: widget.onChanged,
            decoration: InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Type',
              hintStyle: TextStyle(
                color: widget.textColor.withValues(alpha: 0.45),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
              isCollapsed: true,
            ),
            cursorColor: widget.textColor,
            style: TextStyle(
              color: widget.textColor,
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

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
      'diamond' => _diamond(shapeRect),
      'triangle' => _triangle(shapeRect),
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

Path _diamond(Rect rect) {
  return Path()
    ..moveTo(rect.center.dx, rect.top)
    ..lineTo(rect.right, rect.center.dy)
    ..lineTo(rect.center.dx, rect.bottom)
    ..lineTo(rect.left, rect.center.dy)
    ..close();
}

Path _triangle(Rect rect) {
  return Path()
    ..moveTo(rect.center.dx, rect.top)
    ..lineTo(rect.right, rect.bottom)
    ..lineTo(rect.left, rect.bottom)
    ..close();
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
