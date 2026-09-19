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
                isComplex: true,
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

      final fill =
          isProcessing
              ? colors.accentGreen
              : panelTypeColor(
                panel.type,
                colors,
                override: panel.color,
              ).withAlpha(0xCC);
      canvas.drawRRect(rrect, Paint()..color = fill);
      _paintPanelTitle(canvas, rrect, panel.title, fill);
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

  /// Minimum scaled rect size for the title to stay legible on the map.
  static const double _minTitleHeight = 9.0;
  static const double _minTitleWidth = 16.0;

  static final Map<String, TextPainter> _titlePainters = {};

  /// Draws the panel title inside its minimap rect, wrapping to the next
  /// line when it does not fit; clipped to the rect so overflow never spills
  /// onto neighbouring panels.
  void _paintPanelTitle(Canvas canvas, RRect rrect, String title, Color fill) {
    final trimmed = title.trim();
    final rect = rrect.outerRect;
    if (trimmed.isEmpty ||
        rect.height < _minTitleHeight ||
        rect.width < _minTitleWidth) {
      return;
    }
    final fontSize = math.min(8.5, math.max(6.0, rect.height - 3.0));
    final maxWidth = rect.width - 5.0;
    final maxLines = math.max(1, ((rect.height - 3.0) / fontSize).floor());
    final tp = _laidOutTitlePainter(
      trimmed,
      fontSize,
      maxWidth,
      maxLines,
      fill,
    );
    canvas.save();
    canvas.clipRRect(rrect);
    tp.paint(canvas, Offset(rect.left + 2.5, rect.center.dy - tp.height / 2));
    canvas.restore();
  }

  /// Returns a laid-out [TextPainter] for the title, cached by its inputs so
  /// panning/zooming does not re-run text layout on every frame. Width is
  /// quantized to whole pixels to keep the cache hit-rate high while zooming.
  static TextPainter _laidOutTitlePainter(
    String title,
    double fontSize,
    double maxWidth,
    int maxLines,
    Color fill,
  ) {
    final textColor = readableTextColor(fill);
    final key = '$title\x1F$fontSize\x1F${maxWidth.round()}'
        '\x1F$maxLines\x1F${textColor.toARGB32()}';
    var tp = _titlePainters[key];
    if (tp == null) {
      if (_titlePainters.length > 512) _titlePainters.clear();
      tp =
          TextPainter(
              text: TextSpan(
                text: title,
                style: TextStyle(
                  color: textColor,
                  fontSize: fontSize,
                  height: 1.0,
                  fontWeight: FontWeight.w600,
                ),
              ),
              maxLines: maxLines,
              ellipsis: '…',
              textDirection: TextDirection.ltr,
            )
            ..layout(maxWidth: maxWidth);
      _titlePainters[key] = tp;
    }
    return tp;
  }

  /// Contrast-safe text color that stays readable on ANY panel fill:
  /// dark ink on light fills, near-white on dark fills. Derived from the
  /// fill's own hue (desaturated) so the ink harmonizes with the panel.
  static Color readableTextColor(Color background) {
    final hsl = HSLColor.fromColor(background);
    final darkInk = background.computeLuminance() > 0.55;
    return hsl
        .withSaturation(math.min(hsl.saturation, 0.25))
        .withLightness(darkInk ? 0.10 : 0.94)
        .toColor();
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
