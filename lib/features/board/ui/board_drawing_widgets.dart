import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Drawing widget — renders a completed BoardDrawingElement as a draggable item
// Caller is responsible for positioning (Positioned must be direct Stack child)
// ─────────────────────────────────────────────────────────────────────────────

class BoardDrawingWidget extends StatefulWidget {
  const BoardDrawingWidget({
    required this.drawing,
    required this.isSelectMode,
    required this.onMove,
    required this.onDelete,
  });

  final BoardDrawingElement drawing;
  final bool isSelectMode;
  final ValueChanged<Offset> onMove;
  final VoidCallback onDelete;

  @override
  State<BoardDrawingWidget> createState() => BoardDrawingWidgetState();
}

class BoardDrawingWidgetState extends State<BoardDrawingWidget> {
  bool _hovered = false;
  bool _selected = false;

  bool get _showBadge => widget.isSelectMode && (_hovered || _selected);

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        StrokeHitTestBox(
          drawing: widget.drawing,
          onHoverChanged: (h) {
            if (_hovered != h) setState(() => _hovered = h);
          },
          child: GestureDetector(
            onTap:
                widget.isSelectMode
                    ? () => setState(() => _selected = !_selected)
                    : null,
            onPanUpdate:
                widget.isSelectMode
                    ? (d) => widget.onMove(widget.drawing.position + d.delta)
                    : null,
            child: CustomPaint(
              size: widget.drawing.size,
              painter: DrawingElementPainter(drawing: widget.drawing),
            ),
          ),
        ),
        // Delete badge OUTSIDE StrokeHitTestBox so it has its own hit area
        if (_showBadge)
          Positioned(
            right: -6,
            top: -6,
            child: GestureDetector(
              onTap: widget.onDelete,
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: context.appColors.statusError.withAlpha(204),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: context.appColors.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Paints a [BoardDrawingElement]'s strokes on the given canvas.
class DrawingElementPainter extends CustomPainter {
  const DrawingElementPainter({required this.drawing});

  final BoardDrawingElement drawing;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = drawing.strokeColor
          ..strokeWidth = drawing.strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant DrawingElementPainter oldDelegate) {
    return oldDelegate.drawing != drawing;
  }

  /// Only return true when [position] is within hit distance of an actual
  /// stroke segment. Transparent bbox areas return null (miss) so panels
  /// underneath can still handle pointer events.
  @override
  bool? hitTest(Offset position) {
    final hitRadius = (drawing.strokeWidth / 2) + 8.0;
    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        if ((stroke.first - position).distance <= hitRadius) return true;
        continue;
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        if (_distToSegment(position, stroke[i], stroke[i + 1]) <= hitRadius) {
          return true;
        }
      }
    }
    return null; // transparent — let events fall through
  }

  static double _distToSegment(Offset p, Offset a, Offset b) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final lenSq = dx * dx + dy * dy;
    final t =
        lenSq == 0 ? 0.0 : ((p.dx - a.dx) * dx + (p.dy - a.dy) * dy) / lenSq;
    final closest = Offset(
      a.dx + t.clamp(0.0, 1.0) * dx,
      a.dy + t.clamp(0.0, 1.0) * dy,
    );
    return (p - closest).distance;
  }

  /// Public stroke hit test used by [StrokeHitTestRenderBox].
  static bool strokeHitTest(BoardDrawingElement drawing, Offset position) {
    final hitRadius = (drawing.strokeWidth / 2) + 8.0;
    for (final stroke in drawing.strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        if ((stroke.first - position).distance <= hitRadius) return true;
        continue;
      }
      for (int i = 0; i < stroke.length - 1; i++) {
        if (_distToSegment(position, stroke[i], stroke[i + 1]) <= hitRadius) {
          return true;
        }
      }
    }
    return false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// StrokeHitTestBox — SingleChildRenderObjectWidget whose RenderBox only
// returns true from hitTest when the pointer is near an actual drawn stroke.
// Transparent bbox areas pass through to panels below.
// ─────────────────────────────────────────────────────────────────────────────

class StrokeHitTestBox extends SingleChildRenderObjectWidget {
  const StrokeHitTestBox({
    required this.drawing,
    required this.onHoverChanged,
    required super.child,
  });

  final BoardDrawingElement drawing;
  final ValueChanged<bool> onHoverChanged;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return StrokeHitTestRenderBox(
      drawing: drawing,
      onHoverChanged: onHoverChanged,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant StrokeHitTestRenderBox renderObject,
  ) {
    renderObject
      ..drawing = drawing
      ..onHoverChanged = onHoverChanged;
  }
}

class StrokeHitTestRenderBox extends RenderProxyBox {
  StrokeHitTestRenderBox({
    required BoardDrawingElement drawing,
    required this.onHoverChanged,
  }) : _drawing = drawing;

  BoardDrawingElement _drawing;
  set drawing(BoardDrawingElement value) {
    if (_drawing == value) return;
    _drawing = value;
    markNeedsPaint();
  }

  ValueChanged<bool> onHoverChanged;

  bool _lastHover = false;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    // Only hit if pointer is near a stroke
    if (!DrawingElementPainter.strokeHitTest(_drawing, position)) {
      if (_lastHover) {
        _lastHover = false;
        // Schedule callback to avoid calling during hit test
        WidgetsBinding.instance.addPostFrameCallback((_) {
          onHoverChanged(false);
        });
      }
      return false;
    }
    if (!_lastHover) {
      _lastHover = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        onHoverChanged(true);
      });
    }
    // Let child handle the event
    return super.hitTest(result, position: position);
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    super.handleEvent(event, entry);
    if (event is PointerExitEvent || event is PointerCancelEvent) {
      if (_lastHover) {
        _lastHover = false;
        onHoverChanged(false);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Active stroke painter (board-space points)
// ─────────────────────────────────────────────────────────────────────────────

class ActiveStrokePainter extends CustomPainter {
  const ActiveStrokePainter({
    required this.points,
    required this.origin,
    required this.color,
    required this.strokeWidth,
  });

  final List<Offset> points;
  final Offset origin;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.length < 2) return;
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke;

    final path =
        Path()
          ..moveTo(points.first.dx + origin.dx, points.first.dy + origin.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx + origin.dx, points[i].dy + origin.dy);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant ActiveStrokePainter oldDelegate) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Connect preview painter
// ─────────────────────────────────────────────────────────────────────────────

class ConnectPreviewPainter extends CustomPainter {
  const ConnectPreviewPainter({
    required this.panels,
    required this.sourceId,
    required this.targetPoint,
    required this.origin,
    required this.color,
  });

  final List<BoardPanelInstance> panels;
  final String sourceId;
  final Offset targetPoint;
  final Offset origin;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final source = panels.where((p) => p.id == sourceId).firstOrNull;
    if (source == null) return;

    final srcRect = source.bounds.rect.translate(origin.dx, origin.dy);
    final target = Offset(
      targetPoint.dx + origin.dx,
      targetPoint.dy + origin.dy,
    );
    // Start from panel edge toward the cursor
    final srcEdge = BoardLinksPainter.edgePointToward(srcRect, target);

    final paint =
        Paint()
          ..color = color.withAlpha(180)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke;

    final path =
        Path()
          ..moveTo(srcEdge.dx, srcEdge.dy)
          ..cubicTo(
            srcEdge.dx + (target.dx - srcEdge.dx) * 0.4,
            srcEdge.dy,
            srcEdge.dx + (target.dx - srcEdge.dx) * 0.6,
            target.dy,
            target.dx,
            target.dy,
          );
    // Draw dashed
    for (final metric in path.computeMetrics()) {
      double dist = 0;
      bool draw = true;
      while (dist < metric.length) {
        final next = math.min(dist + (draw ? 8.0 : 6.0), metric.length);
        if (draw) canvas.drawPath(metric.extractPath(dist, next), paint);
        dist = next;
        draw = !draw;
      }
    }
  }

  @override
  bool shouldRepaint(covariant ConnectPreviewPainter oldDelegate) => true;
}
