import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Paints all board links between panels.
class BoardLinksPainter extends CustomPainter {
  const BoardLinksPainter({
    required this.panels,
    required this.links,
    required this.origin,
  });

  final List<BoardPanelInstance> panels;
  final List<BoardPanelLink> links;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    final panelMap = {for (final panel in panels) panel.id: panel};
    for (final link in links) {
      final from = panelMap[link.fromPanelId];
      final to = panelMap[link.toPanelId];
      if (from == null || to == null || from.hidden || to.hidden) continue;

      final fromRect = from.bounds.rect.translate(origin.dx, origin.dy);
      final toRect = to.bounds.rect.translate(origin.dx, origin.dy);
      final start = _edgePointToward(fromRect, toRect.center);
      final end = _edgePointToward(toRect, fromRect.center);
      final path = _buildLinkPath(start, end, link.geometry);

      final paint =
          Paint()
            ..color = link.color.withAlpha(
              link.behavior == BoardLinkBehavior.dynamic ? 220 : 200,
            )
            ..style = PaintingStyle.stroke
            ..strokeWidth =
                link.behavior == BoardLinkBehavior.dynamic ? 2.6 : 2.0
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

      if (link.behavior == BoardLinkBehavior.dynamic) {
        _drawDashedPath(canvas, path, paint);
      } else {
        canvas.drawPath(path, paint);
      }

      if (link.style == BoardLinkStyle.arrow) {
        _drawArrowHead(canvas, paint, path, end);
      }
    }
  }

  static Path buildLinkPath(
    Offset start,
    Offset end,
    BoardLinkGeometry geometry,
  ) => _buildLinkPath(start, end, geometry);

  static Path _buildLinkPath(
    Offset start,
    Offset end,
    BoardLinkGeometry geometry,
  ) {
    switch (geometry) {
      case BoardLinkGeometry.straight:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(end.dx, end.dy);
      case BoardLinkGeometry.elbow:
        final midX = (start.dx + end.dx) / 2;
        return Path()
          ..moveTo(start.dx, start.dy)
          ..lineTo(midX, start.dy)
          ..lineTo(midX, end.dy)
          ..lineTo(end.dx, end.dy);
      case BoardLinkGeometry.bezier:
        return Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + ((end.dx - start.dx) * 0.35),
            start.dy,
            end.dx - ((end.dx - start.dx) * 0.35),
            end.dy,
            end.dx,
            end.dy,
          );
    }
  }

  /// Returns the point on [rect]'s border in the direction of [target]
  /// from the rect's center. Used to start/end links at panel edges.
  static Offset edgePointToward(Rect rect, Offset target) =>
      _edgePointToward(rect, target);

  static Offset _edgePointToward(Rect rect, Offset target) {
    final cx = rect.center.dx;
    final cy = rect.center.dy;
    final dx = target.dx - cx;
    final dy = target.dy - cy;
    if (dx.abs() < 0.001 && dy.abs() < 0.001) return rect.center;
    double t = double.infinity;
    if (dx > 0) t = math.min(t, (rect.right - cx) / dx);
    if (dx < 0) t = math.min(t, (rect.left - cx) / dx);
    if (dy > 0) t = math.min(t, (rect.bottom - cy) / dy);
    if (dy < 0) t = math.min(t, (rect.top - cy) / dy);
    return Offset(cx + dx * t, cy + dy * t);
  }

  void _drawDashedPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      double distance = 0;
      const dash = 10.0;
      const gap = 8.0;
      while (distance < metric.length) {
        final next = math.min(distance + dash, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += dash + gap;
      }
    }
  }

  void _drawArrowHead(
    Canvas canvas,
    Paint paint,
    Path path,
    Offset fallbackEnd,
  ) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.last;
    // Sample tangent slightly before the end for reliable direction
    final sampleAt = (metric.length - 2.0).clamp(0.0, metric.length);
    final tangent = metric.getTangentForOffset(sampleAt);
    if (tangent == null) return;

    // Compute angle from sample point toward the tip
    final tip =
        metric.getTangentForOffset(metric.length)?.position ?? tangent.position;
    final dir = tip - tangent.position;
    final angle =
        dir.distance > 0.5 ? math.atan2(dir.dy, dir.dx) : tangent.angle;

    const arrowSize = 13.0;
    final p1 = Offset(
      tip.dx - arrowSize * math.cos(angle - math.pi / 5),
      tip.dy - arrowSize * math.sin(angle - math.pi / 5),
    );
    final p2 = Offset(
      tip.dx - arrowSize * math.cos(angle + math.pi / 5),
      tip.dy - arrowSize * math.sin(angle + math.pi / 5),
    );

    final arrowPaint =
        Paint()
          ..color = paint.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = paint.strokeWidth.clamp(1.5, 2.5)
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    final arrow =
        Path()
          ..moveTo(p1.dx, p1.dy)
          ..lineTo(tip.dx, tip.dy)
          ..lineTo(p2.dx, p2.dy);
    canvas.drawPath(arrow, arrowPaint);
  }

  @override
  bool shouldRepaint(covariant BoardLinksPainter oldDelegate) {
    return oldDelegate.panels != panels ||
        oldDelegate.links != links ||
        oldDelegate.origin != origin;
  }
}
