import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

class BoardOverviewPreview extends StatelessWidget {
  const BoardOverviewPreview({required this.board});

  final BoardDocument board;

  /// Standard viewport size used when computing visible bounds from saved
  /// viewport state. Approximates a typical MacBook screen size.
  static const Size _standardViewportSize = Size(1440, 900);

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panels = board.panels.where((panel) => !panel.hidden).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (panels.isEmpty) {
          return ColoredBox(
            color: colors.background,
            child: Center(
              child: Container(
                width: math.min(size.width, 120),
                height: math.min(size.height, 70),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.border),
                ),
                child: Icon(
                  Icons.dashboard_outlined,
                  color:
                      Theme.of(context).textTheme.bodySmall?.color ??
                      Theme.of(context).colorScheme.onSurface,
                  size: 26,
                ),
              ),
            ),
          );
        }

        // If the user has saved a non-default viewport (zoomed / panned),
        // show the board from that saved position instead of fitting all.
        // Otherwise fall back to fit-all.
        final vp = board.viewport;
        final Rect bounds;
        if (_isNonDefaultViewport(vp)) {
          bounds = _visibleBoundsFromViewport(vp);
        } else {
          bounds = boundsForPanels(panels).inflate(120);
        }

        final scale = math.min(
          size.width / bounds.width,
          size.height / bounds.height,
        );
        final dx = (size.width - bounds.width * scale) / 2;
        final dy = (size.height - bounds.height * scale) / 2;

        return ColoredBox(
          color: colors.background,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: BoardOverviewLinksPainter(
                    links: board.links,
                    panels: panels,
                    bounds: bounds,
                    scale: scale,
                    dx: dx,
                    dy: dy,
                  ),
                ),
              ),
              for (final panel in panels)
                Positioned.fromRect(
                  rect: mapPanelRect(panel.bounds.rect, bounds, scale, dx, dy),
                  child: BoardOverviewPanelPreview(panel: panel),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _isNonDefaultViewport(BoardViewport vp) {
    // Consider non-default if scale deviates significantly from 1.0 or
    // user has panned more than a minimal amount.
    return vp.scale != 1.0 || vp.translation != Offset.zero;
  }

  /// Compute the visible board-coordinate rect from the saved viewport.
  ///
  /// The board uses transform: screenPos = boardPos * scale + translation
  /// (canvas origin is already folded into translation by _saveViewport).
  /// So the visible board rect at a standard 1440×900 viewport is:
  ///   left = -translation.dx / scale
  ///   top  = -translation.dy / scale
  ///   size = standardViewportSize / scale
  Rect _visibleBoundsFromViewport(BoardViewport vp) {
    final s = vp.scale;
    final tx = vp.translation.dx;
    final ty = vp.translation.dy;
    final vw = _standardViewportSize.width;
    final vh = _standardViewportSize.height;
    return Rect.fromLTWH(-tx / s, -ty / s, vw / s, vh / s);
  }

  Rect boundsForPanels(List<BoardPanelInstance> panels) {
    var bounds = panels.first.bounds.rect;
    for (final panel in panels.skip(1)) {
      bounds = bounds.expandToInclude(panel.bounds.rect);
    }
    return bounds;
  }

  Rect mapPanelRect(Rect rect, Rect bounds, double scale, double dx, double dy) {
    return Rect.fromLTWH(
      dx + (rect.left - bounds.left) * scale,
      dy + (rect.top - bounds.top) * scale,
      math.max(12, rect.width * scale),
      math.max(9, rect.height * scale),
    );
  }
}

class BoardOverviewLinksPainter extends CustomPainter {
  const BoardOverviewLinksPainter({
    required this.links,
    required this.panels,
    required this.bounds,
    required this.scale,
    required this.dx,
    required this.dy,
  });

  final List<BoardPanelLink> links;
  final List<BoardPanelInstance> panels;
  final Rect bounds;
  final double scale;
  final double dx;
  final double dy;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final from = panels.where((p) => p.id == link.fromPanelId).firstOrNull;
      final to = panels.where((p) => p.id == link.toPanelId).firstOrNull;
      if (from == null || to == null) continue;
      canvas.drawLine(
        _mapPoint(from.bounds.rect.center),
        _mapPoint(to.bounds.rect.center),
        Paint()
          ..color = link.color.withAlpha(120)
          ..strokeWidth = 1.2,
      );
    }
  }

  Offset _mapPoint(Offset point) {
    return Offset(
      dx + (point.dx - bounds.left) * scale,
      dy + (point.dy - bounds.top) * scale,
    );
  }

  @override
  bool shouldRepaint(covariant BoardOverviewLinksPainter oldDelegate) {
    return oldDelegate.links != links ||
        oldDelegate.panels != panels ||
        oldDelegate.bounds != bounds ||
        oldDelegate.scale != scale ||
        oldDelegate.dx != dx ||
        oldDelegate.dy != dy;
  }
}

class BoardOverviewPanelPreview extends StatelessWidget {
  const BoardOverviewPanelPreview({required this.panel});

  final BoardPanelInstance panel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 54 || constraints.maxHeight < 38;
        final textColor = Theme.of(context).colorScheme.onSurface;
        final muted =
            Theme.of(context).textTheme.bodySmall?.color ??
            textColor.withAlpha(140);
        return ClipRRect(
          borderRadius: BorderRadius.circular(tiny ? 3 : 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.background,
              borderRadius: BorderRadius.circular(tiny ? 3 : 6),
              border: Border.all(color: colors.divider, width: 0.5),
            ),
            child:
                tiny
                    ? const SizedBox.expand()
                    : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          color: colors.divider.withAlpha(30),
                          child: Row(
                            children: [
                              Icon(
                                iconForPanelType(panel.type),
                                size: 9,
                                color: muted,
                              ),
                              const SizedBox(width: 3),
                              Expanded(
                                child: Text(
                                  panel.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 7,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: ClipRect(
                            child: BoardOverviewPanelContent(panel: panel),
                          ),
                        ),
                      ],
                    ),
          ),
        );
      },
    );
  }
}

/// Renders the real plugin widget scaled to fit the preview area.
///
/// Uses [Transform.scale] so layout is stable, and [LayoutBuilder] to compute
/// the correct scale factor from the panel's actual design size.
/// Any exceptions thrown during build are surfaced via [ErrorWidget.builder]
/// (overridden in [BoardOffscreenRenderer] to log + return a grey box).
class BoardOverviewPanelContent extends StatelessWidget {
  const BoardOverviewPanelContent({required this.panel});

  final BoardPanelInstance panel;

  static final BoardPanelRenderContext _noOp = BoardPanelRenderContext(
    isSelected: false,
    onFocus: () {},
    onDelete: () {},
    onUpdateState: (_) {},
    onShowEditor: () {},
  );

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plugin =
            BoardPluginRegistry.instance.pluginFor(panel.type) ??
            BoardPluginRegistry.instance.fallback;

        final panelW = panel.bounds.width.clamp(60.0, 4000.0);
        final panelH = panel.bounds.height.clamp(60.0, 4000.0);
        final availW = constraints.maxWidth;
        final availH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : panelH;

        final scale = math.min(availW / panelW, availH / panelH);

        // Plugins that initialise native code (MPV, WebView, PTY) on widget
        // creation will crash the process in a headless context. Show a
        // labelled placeholder instead of calling buildContent for them.
        final Widget child;
        if (!plugin.supportsHeadlessRender) {
          child = Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  plugin.icon,
                  size: 32,
                  color: const Color(0x809E9E9E),
                ),
                const SizedBox(height: 6),
                Text(
                  plugin.displayName,
                  style: const TextStyle(
                    color: Color(0x809E9E9E),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          );
        } else {
          child = plugin.buildContent(context, panel, _noOp);
        }

        return SizedBox(
          width: availW,
          height: availH,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: panelW,
              height: panelH,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

Color panelTypeColor(String type, {Color? override}) {
  if (override != null) return override;
  return switch (type) {
    'board.note.markdown' => const Color(0xFFE879F9),
    'board.kanban' => const Color(0xFF6366F1),
    'board.webpage' => const Color(0xFF0EA5E9),
    'board.code.snippet' => const Color(0xFF10B981),
    'board.checklist' => const Color(0xFFF59E0B),
    'board.files' => const Color(0xFFEC4899),
    'board.file.preview' => const Color(0xFF8B5CF6),
    'board.playlist' => const Color(0xFFA855F7),
    'board.run_configs' => const Color(0xFF22C55E),
    'board.run' => const Color(0xFF84CC16),
    'board.chat' => const Color(0xFF34D399),
    'board.terminal' => const Color(0xFF14B8A6),
    'board.filetree' => const Color(0xFF64748B),
    'board.diff.preview' => const Color(0xFF60A5FA),
    'board.yolo_assistant' => const Color(0xFFF97316),
    'board.widget.custom' => const Color(0xFF7C3AED),
    'board.timer' => const Color(0xFF3B82F6),
    _ => const Color(0xFF94A3B8),
  };
}

IconData iconForPanelType(String type) {
  return BoardPluginRegistry.instance.pluginFor(type)?.icon ??
      Icons.widgets_outlined;
}
