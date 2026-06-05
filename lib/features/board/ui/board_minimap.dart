import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';

class BoardMiniMap extends StatelessWidget {
  const BoardMiniMap({
    super.key,
    required this.panels,
    required this.processingPanelIds,
    required this.transformCtrl,
    required this.viewportSize,
    required this.origin,
    required this.onPanTo,
  });

  final List<BoardPanelInstance> panels;
  final Set<String> processingPanelIds;
  final TransformationController transformCtrl;
  final Size viewportSize;
  final Offset origin;
  final ValueChanged<Offset> onPanTo;

  static const double _mapW = 210.0;
  static const double _mapH = 130.0;
  static const double _padding = 180.0;

  Rect _canvasBounds(Rect viewportRect) {
    final visiblePanels = panels.where((panel) => !panel.hidden).toList();
    if (visiblePanels.isEmpty) {
      return viewportRect.inflate(_padding);
    }
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = -double.infinity;
    double maxY = -double.infinity;
    for (final panel in visiblePanels) {
      final rect = panel.bounds.rect;
      if (rect.left < minX) minX = rect.left;
      if (rect.top < minY) minY = rect.top;
      if (rect.right > maxX) maxX = rect.right;
      if (rect.bottom > maxY) maxY = rect.bottom;
    }
    final contentBounds = Rect.fromLTRB(
      minX - _padding,
      minY - _padding,
      maxX + _padding,
      maxY + _padding,
    );
    return contentBounds.expandToInclude(viewportRect).inflate(_padding);
  }

  void _handleGesture(Offset local, Rect bounds) {
    final cx = bounds.left + (local.dx / _mapW) * bounds.width;
    final cy = bounds.top + (local.dy / _mapH) * bounds.height;
    onPanTo(Offset(cx, cy));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: transformCtrl,
      builder: (context, _) {
        final vpTL = transformCtrl.toScene(Offset.zero) - origin;
        final vpBR =
            transformCtrl.toScene(
              Offset(viewportSize.width, viewportSize.height),
            ) -
            origin;
        final viewportRect = Rect.fromLTRB(vpTL.dx, vpTL.dy, vpBR.dx, vpBR.dy);
        final bounds = _canvasBounds(viewportRect);
        return GestureDetector(
          onTapDown: (details) => _handleGesture(details.localPosition, bounds),
          onPanUpdate:
              (details) => _handleGesture(details.localPosition, bounds),
          child: Container(
            width: _mapW,
            height: _mapH,
            decoration: BoxDecoration(
              color: colors.surface.withAlpha(0xE5),
              border: Border.all(color: colors.primary.withAlpha(0x50)),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: colors.background.withAlpha(102),
                  blurRadius: 10,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: CustomPaint(
                painter: BoardMiniMapPainter(
                  panels: panels.where((panel) => !panel.hidden).toList(),
                  processingPanelIds: processingPanelIds,
                  bounds: bounds,
                  viewportRect: viewportRect,
                  colors: colors,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class BoardMiniMapPainter extends CustomPainter {
  const BoardMiniMapPainter({
    required this.panels,
    required this.processingPanelIds,
    required this.bounds,
    required this.viewportRect,
    required this.colors,
  });

  final List<BoardPanelInstance> panels;
  final Set<String> processingPanelIds;
  final Rect bounds;
  final Rect viewportRect;
  final AppColorScheme colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final scaleX = size.width / bounds.width;
    final scaleY = size.height / bounds.height;

    for (final panel in panels) {
      final rect = panel.bounds.rect;
      final x = (rect.left - bounds.left) * scaleX;
      final y = (rect.top - bounds.top) * scaleY;
      final w = math.max(4.0, rect.width * scaleX);
      final h = math.max(3.0, rect.height * scaleY);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(x, y, w, h),
        const Radius.circular(1.5),
      );

      final isProcessing = processingPanelIds.contains(panel.id);

      if (isProcessing) {
        // Draw glow behind processing panels
        canvas.drawRRect(
          rrect.inflate(2),
          Paint()
            ..color = colors.accentGreen
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
      }

      canvas.drawRRect(
        rrect,
        Paint()
          ..color =
              isProcessing
                  ? colors.accentGreen
                  : panelTypeColor(
                    panel.type,
                    colors,
                    override: panel.color,
                  ).withAlpha(0xCC),
      );
    }

    final vx = (viewportRect.left - bounds.left) * scaleX;
    final vy = (viewportRect.top - bounds.top) * scaleY;
    final vw = math.max(8.0, viewportRect.width * scaleX);
    final vh = math.max(8.0, viewportRect.height * scaleY);
    final viewport = RRect.fromRectAndRadius(
      Rect.fromLTWH(vx, vy, vw, vh),
      const Radius.circular(3),
    );
    canvas.drawRRect(
      viewport,
      Paint()..color = colors.accentBlue.withAlpha(32),
    );
    canvas.drawRRect(
      viewport,
      Paint()
        ..color = colors.accentBlue.withAlpha(204)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
  }

  @override
  bool shouldRepaint(covariant BoardMiniMapPainter oldDelegate) {
    return oldDelegate.panels != panels ||
        oldDelegate.bounds != bounds ||
        oldDelegate.viewportRect != viewportRect ||
        oldDelegate.processingPanelIds != processingPanelIds ||
        oldDelegate.colors != colors;
  }
}
