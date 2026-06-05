import 'package:flutter/material.dart';

import 'package:yoloit/features/board/ui/board_math.dart';

class InfiniteBoardGridPainter extends CustomPainter {
  InfiniteBoardGridPainter({
    required this.transformCtrl,
    required this.origin,
    required this.minorColor,
    required this.majorColor,
  }) : super(repaint: transformCtrl);

  final TransformationController transformCtrl;
  final Offset origin;
  final Color minorColor;
  final Color majorColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = matrixScaleOf(
      transformCtrl.value,
    ).clamp(0.0001, 1000.0);
    final translation = transformCtrl.value.storage;
    final tx = translation[12] + (origin.dx * scale);
    final ty = translation[13] + (origin.dy * scale);

    const minorStep = 24.0;
    const majorStep = 120.0;

    final minorSpacing = minorStep * scale;
    final majorSpacing = majorStep * scale;

    final minorPaint =
        Paint()
          ..color = minorColor
          ..strokeWidth = 1;
    final majorPaint =
        Paint()
          ..color = majorColor
          ..strokeWidth = 1;

    double startXMinor = tx % minorSpacing;
    if (startXMinor > 0) startXMinor -= minorSpacing;
    for (double x = startXMinor; x <= size.width; x += minorSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), minorPaint);
    }

    double startYMinor = ty % minorSpacing;
    if (startYMinor > 0) startYMinor -= minorSpacing;
    for (double y = startYMinor; y <= size.height; y += minorSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), minorPaint);
    }

    double startXMajor = tx % majorSpacing;
    if (startXMajor > 0) startXMajor -= majorSpacing;
    for (double x = startXMajor; x <= size.width; x += majorSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), majorPaint);
    }

    double startYMajor = ty % majorSpacing;
    if (startYMajor > 0) startYMajor -= majorSpacing;
    for (double y = startYMajor; y <= size.height; y += majorSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), majorPaint);
    }
  }

  @override
  bool shouldRepaint(covariant InfiniteBoardGridPainter oldDelegate) {
    return oldDelegate.transformCtrl != transformCtrl ||
        oldDelegate.origin != origin ||
        oldDelegate.minorColor != minorColor ||
        oldDelegate.majorColor != majorColor;
  }
}
