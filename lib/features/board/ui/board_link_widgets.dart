import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_links_painter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Link style dialog
// ─────────────────────────────────────────────────────────────────────────────

class LinkStyleChoice {
  const LinkStyleChoice({
    required this.showArrow,
    required this.geometry,
    required this.color,
  });

  final bool showArrow;
  final BoardLinkGeometry geometry;
  final Color color;
}

class LinkStyleDialog extends StatefulWidget {
  const LinkStyleDialog({required this.initialSettings});

  final ConnectSettings initialSettings;

  @override
  State<LinkStyleDialog> createState() => LinkStyleDialogState();
}

class LinkStyleDialogState extends State<LinkStyleDialog> {
  late bool _showArrow;
  late BoardLinkGeometry _geometry;
  late Color _color;

  @override
  void initState() {
    super.initState();
    _showArrow = widget.initialSettings.showArrow;
    _geometry = widget.initialSettings.geometry;
    _color = widget.initialSettings.color;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final mutedColor = context.appColors.textMuted;
    return AlertDialog(
      title: const Text('Link style'),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Live preview ─────────────────────────────────────────────
            Container(
              height: 100,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.border),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: CustomPaint(
                  painter: LinkPreviewPainter(
                    geometry: _geometry,
                    showArrow: _showArrow,
                    color: _color,
                    borderColor: colors.border,
                    panelColor: colors.surface,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Geometry selector ────────────────────────────────────────
            Text(
              'Line style',
              style: TextStyle(fontSize: 12, color: mutedColor),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final geo in BoardLinkGeometry.values) ...[
                  if (BoardLinkGeometry.values.indexOf(geo) > 0)
                    const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _geometry = geo),
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color:
                              _geometry == geo
                                  ? _color.withAlpha(30)
                                  : colors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color:
                                _geometry == geo
                                    ? _color.withAlpha(180)
                                    : colors.border,
                            width: _geometry == geo ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            CustomPaint(
                              size: const Size(48, 24),
                              painter: LinkMiniPreviewPainter(
                                geometry: geo,
                                color: _geometry == geo ? _color : mutedColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              switch (geo) {
                                BoardLinkGeometry.bezier => 'Bezier',
                                BoardLinkGeometry.straight => 'Straight',
                                BoardLinkGeometry.elbow => 'Elbow',
                              },
                              style: TextStyle(
                                fontSize: 10,
                                color: _geometry == geo ? _color : mutedColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            // ── Arrow toggle ─────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Show arrow', style: TextStyle(fontSize: 13)),
                Switch.adaptive(
                  value: _showArrow,
                  onChanged: (v) => setState(() => _showArrow = v),
                  activeColor: _color,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── Color swatches ───────────────────────────────────────────
            Text('Color', style: TextStyle(fontSize: 12, color: mutedColor)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final c in [
                  colors.accentBlue,
                  colors.statusActive,
                  colors.statusError,
                  colors.statusWarning,
                  colors.primaryLight,
                  colors.textPrimary,
                ])
                  GestureDetector(
                    onTap: () => setState(() => _color = c),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              _color == c
                                  ? colors.textPrimary
                                  : colors.textPrimary.withAlpha(30),
                          width: _color == c ? 2.5 : 1,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              () => Navigator.of(context).pop(
                LinkStyleChoice(
                  showArrow: _showArrow,
                  geometry: _geometry,
                  color: _color,
                ),
              ),
          child: const Text('Connect'),
        ),
      ],
    );
  }
}

/// Full-size preview of a link style in the dialog header area.
class LinkPreviewPainter extends CustomPainter {
  const LinkPreviewPainter({
    required this.geometry,
    required this.showArrow,
    required this.color,
    required this.borderColor,
    required this.panelColor,
  });

  final BoardLinkGeometry geometry;
  final bool showArrow;
  final Color color;
  final Color borderColor;
  final Color panelColor;

  @override
  void paint(Canvas canvas, Size size) {
    // Stagger panels vertically so curves are clearly visible
    final start = Offset(size.width * 0.15, size.height * 0.35);
    final end = Offset(size.width * 0.85, size.height * 0.65);

    // Draw mock panels
    final panelPaint =
        Paint()
          ..color = panelColor
          ..style = PaintingStyle.fill;
    final panelBorderPaint =
        Paint()
          ..color = borderColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1;
    final leftPanel = Rect.fromCenter(center: start, width: 56, height: 32);
    final rightPanel = Rect.fromCenter(center: end, width: 56, height: 32);
    final rr = RRect.fromRectAndRadius(leftPanel, const Radius.circular(6));
    final rr2 = RRect.fromRectAndRadius(rightPanel, const Radius.circular(6));
    canvas.drawRRect(rr, panelPaint);
    canvas.drawRRect(rr, panelBorderPaint);
    canvas.drawRRect(rr2, panelPaint);
    canvas.drawRRect(rr2, panelBorderPaint);

    // Shrink endpoints to panel edges
    final lineStart = Offset(leftPanel.right, start.dy);
    final lineEnd = Offset(rightPanel.left, end.dy);

    final path = BoardLinksPainter.buildLinkPath(lineStart, lineEnd, geometry);
    final paint =
        Paint()
          ..color = color.withAlpha(220)
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, paint);

    if (showArrow) {
      _drawArrow(canvas, paint, path, lineEnd);
    }
    // Endpoint dots
    canvas.drawCircle(lineStart, 3, Paint()..color = color.withAlpha(180));
    canvas.drawCircle(lineEnd, 3, Paint()..color = color.withAlpha(180));
  }

  void _drawArrow(Canvas canvas, Paint paint, Path path, Offset end) {
    final metrics = path.computeMetrics().toList();
    if (metrics.isEmpty) return;
    final metric = metrics.last;
    final tangent = metric.getTangentForOffset(metric.length);
    if (tangent == null) return;
    const sz = 11.0;
    final angle = tangent.angle;
    final tip = tangent.position;
    final p1 = Offset(
      tip.dx - sz * math.cos(angle - math.pi / 5),
      tip.dy - sz * math.sin(angle - math.pi / 5),
    );
    final p2 = Offset(
      tip.dx - sz * math.cos(angle + math.pi / 5),
      tip.dy - sz * math.sin(angle + math.pi / 5),
    );
    canvas.drawPath(
      Path()
        ..moveTo(p1.dx, p1.dy)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(p2.dx, p2.dy),
      Paint()
        ..color = paint.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = paint.strokeWidth.clamp(1.5, 2.5)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LinkPreviewPainter old) =>
      old.geometry != geometry ||
      old.showArrow != showArrow ||
      old.color != color ||
      old.borderColor != borderColor ||
      old.panelColor != panelColor;
}

/// Tiny icon-sized link preview used inside the geometry selector buttons.
class LinkMiniPreviewPainter extends CustomPainter {
  const LinkMiniPreviewPainter({required this.geometry, required this.color});

  final BoardLinkGeometry geometry;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    // Stagger Y so bezier/elbow/straight are visually distinct
    final start = Offset(4, size.height * 0.75);
    final end = Offset(size.width - 4, size.height * 0.25);
    final path = BoardLinksPainter.buildLinkPath(start, end, geometry);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant LinkMiniPreviewPainter old) =>
      old.geometry != geometry || old.color != color;
}
