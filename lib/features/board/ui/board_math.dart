import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Extract the 2D uniform scale from a Matrix4.
/// `getMaxScaleOnAxis()` returns max(scaleX, scaleY, 1.0) — wrong when
/// zoomed out (scale < 1) because the Z column is always 1.
double matrixScaleOf(Matrix4 m) {
  final s = m.storage;
  return math.sqrt(s[0] * s[0] + s[1] * s[1]);
}

/// Returns the midpoint of the link curve between [start] and [end].
Offset linkMidpoint(
  Offset start,
  Offset end,
  BoardLinkGeometry geometry,
) {
  switch (geometry) {
    case BoardLinkGeometry.straight:
      return Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    case BoardLinkGeometry.elbow:
      // Mid of the elbow corner
      return Offset(end.dx, start.dy);
    case BoardLinkGeometry.bezier:
      // Sample cubic bezier at t=0.5
      final cx1 = start.dx + (end.dx - start.dx) * 0.35;
      final cy1 = start.dy;
      final cx2 = end.dx - (end.dx - start.dx) * 0.35;
      final cy2 = end.dy;
      const t = 0.5;
      const mt = 1 - t;
      return Offset(
        mt * mt * mt * start.dx +
            3 * mt * mt * t * cx1 +
            3 * mt * t * t * cx2 +
            t * t * t * end.dx,
        mt * mt * mt * start.dy +
            3 * mt * mt * t * cy1 +
            3 * mt * t * t * cy2 +
            t * t * t * end.dy,
      );
  }
}

String fmtDouble(double value) => value.toStringAsFixed(2);

String fmtOffset(Offset offset) =>
    '(${fmtDouble(offset.dx)}, ${fmtDouble(offset.dy)})';

String fmtSize(Size size) => '${fmtDouble(size.width)}x${fmtDouble(size.height)}';

String fmtRect(Rect rect) =>
    'l=${fmtDouble(rect.left)} t=${fmtDouble(rect.top)} r=${fmtDouble(rect.right)} b=${fmtDouble(rect.bottom)}';

String fmtMatrix(Matrix4 matrix) {
  final storage = matrix.storage;
  return 'scale=${fmtDouble(matrixScaleOf(matrix))} t=${fmtOffset(Offset(storage[12], storage[13]))}';
}
