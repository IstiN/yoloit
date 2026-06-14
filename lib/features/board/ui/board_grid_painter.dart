import 'package:flutter/material.dart';

import 'package:yoloit/features/board/ui/board_math.dart';

/// Draws a fixed-size square cell grid over the visible board area.
///
/// Grid lines are drawn at cell boundaries (multiples of [cellSize] + [spacing])
/// in board space. The painter repaints automatically when the transformation
/// controller changes.
class BoardGridPainter extends CustomPainter {
  BoardGridPainter({
    required this.transformCtrl,
    required this.origin,
    required this.cellSize,
    required this.spacing,
    required this.color,
  }) : super(repaint: transformCtrl);

  final TransformationController transformCtrl;
  final Offset origin;
  final double cellSize;
  final double spacing;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = matrixScaleOf(transformCtrl.value).clamp(0.0001, 1000.0);
    final translation = transformCtrl.value.storage;
    final pitch = cellSize + spacing;
    final screenPitch = pitch * scale;

    final baseX = translation[12] + origin.dx * scale;
    final baseY = translation[13] + origin.dy * scale;

    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1;

    var startX = baseX % screenPitch;
    if (startX > 0) startX -= screenPitch;
    for (var x = startX; x <= size.width; x += screenPitch) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    var startY = baseY % screenPitch;
    if (startY > 0) startY -= screenPitch;
    for (var y = startY; y <= size.height; y += screenPitch) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant BoardGridPainter oldDelegate) {
    return oldDelegate.transformCtrl != transformCtrl ||
        oldDelegate.origin != origin ||
        oldDelegate.cellSize != cellSize ||
        oldDelegate.spacing != spacing ||
        oldDelegate.color != color;
  }
}
