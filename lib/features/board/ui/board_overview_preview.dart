import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/ui/widgets/board_panel_chrome.dart';

class BoardOverviewPreview extends StatelessWidget {
  const BoardOverviewPreview({super.key, required this.board});

  final BoardDocument board;

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
                      context.appColors.textMuted,
                  size: 26,
                ),
              ),
            ),
          );
        }

        // Always fit all panels — overview purpose is to show the whole board.
        final bounds = boundsForBoardPanels(panels).inflate(120);

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
                  isComplex: true,
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
                  rect: mapBoardPanelRect(
                    panel.bounds.rect,
                    bounds,
                    scale,
                    dx,
                    dy,
                  ),
                  child: BoardOverviewPanelPreview(panel: panel),
                ),
            ],
          ),
        );
      },
    );
  }

  Rect boundsForPanels(List<BoardPanelInstance> panels) =>
      boundsForBoardPanels(panels);

  Rect mapPanelRect(Rect rect, Rect bounds, double scale, double dx, double dy) =>
      mapBoardPanelRect(rect, bounds, scale, dx, dy);
}

/// Canvas-style preview for offscreen PNG capture: panels at board coordinates
/// with full plugin content (no overview card headers / tiny-mode blanks).
class BoardCanvasPreview extends StatelessWidget {
  const BoardCanvasPreview({super.key, required this.board, this.useViewport = false});

  final BoardDocument board;
  final bool useViewport;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final panels = board.panels.where((panel) => !panel.hidden).toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        if (panels.isEmpty) {
          return ColoredBox(color: colors.background);
        }

        final Matrix4 matrix;
        final bounds = boundsForBoardPanels(panels).inflate(120);

        if (useViewport) {
          matrix = Matrix4.identity()
            ..translate(board.viewport.translation.dx, board.viewport.translation.dy)
            ..scale(board.viewport.scale);
        } else {
          final scale = math.min(
            size.width / bounds.width,
            size.height / bounds.height,
          );
          final dx = (size.width - bounds.width * scale) / 2 - bounds.left * scale;
          final dy = (size.height - bounds.height * scale) / 2 - bounds.top * scale;
          matrix = Matrix4.identity()
            ..translate(dx, dy)
            ..scale(scale);
        }

        return ColoredBox(
          color: colors.background,
          child: Transform(
            transform: matrix,
            alignment: Alignment.topLeft,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: BoardOverviewLinksPainter(
                      links: board.links,
                      panels: panels,
                      bounds: bounds,
                      scale: 1.0,
                      dx: 0.0,
                      dy: 0.0,
                      useViewport: true,
                    ),
                  ),
                ),
                for (final panel in panels)
                  Positioned.fromRect(
                    rect: panel.bounds.rect,
                    child: _OffscreenPanelCard(panel: panel),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

Rect boundsForBoardPanels(List<BoardPanelInstance> panels) {
  var bounds = panels.first.bounds.rect;
  for (final panel in panels.skip(1)) {
    bounds = bounds.expandToInclude(panel.bounds.rect);
  }
  return bounds;
}

Rect mapBoardPanelRect(
  Rect rect,
  Rect bounds,
  double scale,
  double dx,
  double dy,
) {
  return Rect.fromLTWH(
    dx + (rect.left - bounds.left) * scale,
    dy + (rect.top - bounds.top) * scale,
    math.max(12, rect.width * scale),
    math.max(9, rect.height * scale),
  );
}

class BoardOverviewLinksPainter extends CustomPainter {
  const BoardOverviewLinksPainter({
    required this.links,
    required this.panels,
    required this.bounds,
    required this.scale,
    required this.dx,
    required this.dy,
    this.useViewport = false,
  });

  final List<BoardPanelLink> links;
  final List<BoardPanelInstance> panels;
  final Rect bounds;
  final double scale;
  final double dx;
  final double dy;
  final bool useViewport;

  @override
  void paint(Canvas canvas, Size size) {
    for (final link in links) {
      final from = panels.where((p) => p.id == link.fromPanelId).firstOrNull;
      final to = panels.where((p) => p.id == link.toPanelId).firstOrNull;
      if (from == null || to == null) continue;
      
      final fromPt = from.bounds.rect.center;
      final toPt = to.bounds.rect.center;

      if (useViewport) {
        canvas.drawLine(
          fromPt,
          toPt,
          Paint()
            ..color = link.color.withAlpha(120)
            ..strokeWidth = 1.2,
        );
      } else {
        canvas.drawLine(
          _mapPoint(fromPt),
          _mapPoint(toPt),
          Paint()
            ..color = link.color.withAlpha(120)
            ..strokeWidth = 1.2,
        );
      }
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
        oldDelegate.dy != dy ||
        oldDelegate.useViewport != useViewport;
  }
}

class BoardOverviewPanelPreview extends StatelessWidget {
  const BoardOverviewPanelPreview({super.key, required this.panel});

  final BoardPanelInstance panel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiny = constraints.maxWidth < 54 || constraints.maxHeight < 38;
        final textColor = Theme.of(context).colorScheme.onSurface;
        final muted =
            context.appColors.textMuted;
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
                            child: BoardOverviewPanelContent(
                              panel: panel,
                              headerHeight: 18.0,
                            ),
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
  const BoardOverviewPanelContent({super.key, required this.panel, this.headerHeight = 0.0});

  final BoardPanelInstance panel;
  final double headerHeight;

  BoardPanelRenderContext _renderContext(BuildContext context) {
    BoardPanelInstance? findPanel(String id) {
      try {
        final board = context.read<BoardCubit>().state.activeBoard;
        if (board == null) return null;
        for (final panel in board.panels) {
          if (panel.id == id) return panel;
          if (panel.type == 'board.table') {
            final customId =
                (panel.state['tableId'] as String?)?.trim() ?? '';
            if (customId.isNotEmpty && customId == id) return panel;
          }
        }
        return null;
      } catch (_) {
        return null;
      }
    }

    return BoardPanelRenderContext(
      isSelected: false,
      onFocus: () {},
      onDelete: () {},
      onUpdateState: (_) {},
      onShowEditor: () {},
      isHeadlessPreview: true,
      onFindPanelById: findPanel,
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final plugin =
            BoardPluginRegistry.instance.pluginFor(panel.type) ??
            BoardPluginRegistry.instance.fallback;

        final panelW = panel.bounds.width.clamp(60.0, 4000.0);
        final panelH = (panel.bounds.height - headerHeight).clamp(60.0, 4000.0);
        final availW = constraints.maxWidth;
        final availH =
            constraints.maxHeight.isFinite ? constraints.maxHeight : panelH;

        final isFullScaleCanvas = headerHeight == 44.0;
        final scale = isFullScaleCanvas ? 1.0 : math.min(availW / panelW, availH / panelH);

        // Plugins that initialise native code (MPV, WebView, PTY) on widget
        // creation will crash the process in a headless context. Show a
        // detailed, realistic visual mockup instead of calling buildContent.
        // We selectively allow Custom JS Widgets to render on the full-scale offscreen
        // canvas, as it is a single-pass render and does not trigger JSC rapid dispose crashes.
        final Widget child;
        final supportsRender = plugin.supportsHeadlessRender || 
            (isFullScaleCanvas && panel.type == 'board.widget.custom');

        if (!supportsRender) {
          child = _buildHeadlessMockup(context, panel, plugin);
        } else {
          // Mark previews as headless so shared engine-backed content (e.g.
          // scene3d GameWidget) renders a placeholder instead of stealing the
          // single attachment from the live panel on the board canvas.
          child = ScrollConfiguration(
            behavior: const HeadlessScrollBehavior(),
            child: _PreviewSafePanelShell(
              child: plugin.buildContent(context, panel, _renderContext(context)),
            ),
          );
        }

        // Use OverflowBox to allow the child to lay out at its full design size
        // (panelW x panelH) regardless of parent constraints. Transform.scale
        // then paints the child perfectly shrunk down.
        return SizedBox(
          width: availW,
          height: availH,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: panelW,
              maxWidth: panelW,
              minHeight: panelH,
              maxHeight: panelH,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

/// Supplies [Material] for buttons and disables [Tooltip] overlay insertion
/// during scaled overview previews (live cards + offscreen PNG capture).
class _PreviewSafePanelShell extends StatelessWidget {
  const _PreviewSafePanelShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: false,
      child: Material(
        type: MaterialType.transparency,
        child: Overlay(
          initialEntries: [
            OverlayEntry(
              builder: (context) => TooltipVisibility(
                visible: false,
                // Disable text selection inside scaled/headless previews so that
                // plugins containing SelectionArea do not schedule post-dispose
                // updates on inactive elements when the preview tree is torn
                // down during board switches.
                child: SelectionContainer.disabled(child: child),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Color panelTypeColor(String type, AppColorScheme colors, {Color? override}) {
  if (override != null) return override;
  return switch (type) {
    'board.note.markdown' => colors.primaryLight,
    'board.kanban' => colors.primary,
    'board.webpage' => colors.accentBlue,
    'board.code.snippet' => colors.accentGreen,
    'board.checklist' => colors.accentOrange,
    'board.files' => colors.primaryGlow,
    'board.file.preview' => colors.primaryLight,
    'board.playlist' => colors.primaryLight,
    'board.run_configs' => colors.statusActive,
    'board.run' => colors.statusActive,
    'board.chat' => colors.accentGreen,
    'board.terminal' => colors.terminalPrompt,
    'board.filetree' => colors.textMuted,
    'board.diff.preview' => colors.accentBlue,
    'board.yolo_assistant' => colors.accentOrange,
    'board.widget.custom' => colors.primaryDark,
    'board.timer' => colors.accentBlue,
    _ => colors.textMuted,
  };
}

IconData iconForPanelType(String type) {
  return BoardPluginRegistry.instance.pluginFor(type)?.icon ??
      Icons.widgets_outlined;
}

// ─────────────────────────────────────────────────────────────────────────────
// Headless Mockups for Native-Only / Unsupported Plugins
// ─────────────────────────────────────────────────────────────────────────────

Widget _buildHeadlessMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final type = panel.type;
  if (type == 'board.terminal') return _terminalMockup(context, panel);
  if (type == 'board.webpage') return _webpageMockup(context, panel, plugin);
  if (type == 'board.playlist') {
    return _playlistMockup(context, panel, plugin);
  }
  if (type == 'board.run' || type == 'board.run_configs') {
    return _runMockup(context, panel, plugin);
  }
  if (type == 'board.widget.custom') {
    return _customWidgetMockup(context, panel, plugin);
  }
  return _defaultMockup(context, panel, plugin);
}

// Fallback if we don't have custom mocks
Widget _defaultMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final colors = context.appColors;
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          plugin.icon,
          size: 40,
          color: plugin.accentColor.withAlpha(160),
        ),
        const SizedBox(height: 8),
        Text(
          plugin.displayName,
          style: TextStyle(
            color: plugin.accentColor.withAlpha(200),
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          panel.title,
          style: TextStyle(
            color: colors.textMuted.withAlpha(128),
            fontSize: 11,
          ),
        ),
      ],
    ),
  );
}

Widget _terminalMockup(BuildContext context, BoardPanelInstance panel) {
  final colors = context.appColors;
  final stateConfig = panel.state['config'];
  final workingDir = stateConfig is Map
      ? (stateConfig['workingDir'] as String? ?? '')
      : (panel.state['workingDir'] as String? ?? '');
  return Container(
    color: colors.terminalBackground,
    padding: const EdgeInsets.all(12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.statusError,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.statusWarning,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 4),
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: colors.statusActive,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                workingDir.isNotEmpty ? workingDir : 'zsh',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: colors.textPrimary.withAlpha(96),
                  fontSize: 10,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'guest@yoloit:~\$ yoloit status',
          style: TextStyle(
            color: colors.terminalPrompt,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '● YoLoIT Core Services: Active',
          style: TextStyle(
            color: colors.terminalText,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        Text(
          '● Sessions: 2 active, 0 suspended',
          style: TextStyle(
            color: colors.terminalText,
            fontSize: 11,
            fontFamily: 'JetBrainsMono',
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(
              'guest@yoloit:~\$ ',
              style: TextStyle(
                color: colors.terminalPrompt,
                fontSize: 11,
                fontFamily: 'JetBrainsMono',
              ),
            ),
            const _PulsingCursor(),
          ],
        ),
      ],
    ),
  );
}

Widget _webpageMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final colors = context.appColors;
  final url = panel.state['url'] as String? ?? '';
  return Container(
    color: colors.surface,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Browser address bar mockup
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          color: colors.surfaceElevated,
          child: Row(
            children: [
              Icon(
                Icons.arrow_back,
                size: 12,
                color: colors.textPrimary.withAlpha(128),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.arrow_forward,
                size: 12,
                color: colors.textPrimary.withAlpha(64),
              ),
              const SizedBox(width: 6),
              Icon(
                Icons.refresh,
                size: 12,
                color: colors.textPrimary.withAlpha(128),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  height: 20,
                  decoration: BoxDecoration(
                    color: colors.background,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    url.isNotEmpty ? url : 'https://yoloit.ai',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: colors.textPrimary.withAlpha(204),
                      fontSize: 10,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Browser body mockup
        Expanded(
          child: Container(
            color: colors.background,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.language_outlined,
                    size: 36,
                    color: plugin.accentColor.withAlpha(120),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    panel.title.isNotEmpty ? panel.title : 'Webpage Preview',
                    style: TextStyle(
                      color: colors.textPrimary.withAlpha(128),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _playlistMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final colors = context.appColors;
  final rawTracks = panel.state['tracks'] as List? ?? [];
  final tracks = rawTracks.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  final currentIndex = panel.state['currentIndex'] as int? ?? 0;
  return Container(
    color: colors.terminalBackground,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Playlist Header
        Container(
          padding: const EdgeInsets.all(10),
          color: colors.surface,
          child: Row(
            children: [
              Icon(Icons.library_music_outlined, size: 16, color: plugin.accentColor),
              const SizedBox(width: 6),
              const Text(
                'Media Playlist',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
        // Tracks mockup
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Text(
                    'No tracks in playlist',
                    style: TextStyle(
                      color: colors.textPrimary.withAlpha(64),
                      fontSize: 11,
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: tracks.length,
                  itemBuilder: (context, idx) {
                    final track = tracks[idx];
                    final name = track['name'] as String? ?? 'Track ${idx + 1}';
                    final isActive = idx == currentIndex;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      color: isActive ? plugin.accentColor.withAlpha(30) : Colors.transparent,
                      child: Row(
                        children: [
                          Icon(
                            isActive ? Icons.play_arrow_rounded : Icons.music_note_outlined,
                            size: 14,
                            color:
                                isActive
                                    ? plugin.accentColor
                                    : colors.textPrimary.withAlpha(96),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color:
                                    isActive
                                        ? colors.textPrimary
                                        : colors.textPrimary.withAlpha(204),
                                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                          if (isActive)
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(color: plugin.accentColor, shape: BoxShape.circle),
                            ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    ),
  );
}

Widget _runMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final colors = context.appColors;
  final groupName = panel.state['group'] as String? ?? 'default';
  return Container(
    color: colors.background,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Run panel top header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: colors.surface,
          child: Row(
            children: [
              Icon(Icons.play_circle_outline_rounded, size: 16, color: plugin.accentColor),
              const SizedBox(width: 6),
              Text(
                'Run Scope: $groupName',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ],
          ),
        ),
        // Run tasks list mock
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMockRunRow(context, plugin, 'Build Project', 'idle', 'npm run build'),
                _buildMockRunRow(context, plugin, 'Start Dev Server', 'active', 'npm run dev'),
                _buildMockRunRow(context, plugin, 'Lint & Format', 'idle', 'npm run lint'),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _customWidgetMockup(
  BuildContext context,
  BoardPanelInstance panel,
  BoardPanelPlugin plugin,
) {
  final colors = context.appColors;
  final widgetId = panel.state['widgetId'] as String? ?? 'custom-app';
  return Container(
    color: colors.background,
    padding: const EdgeInsets.all(16),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dashboard_customize_outlined, size: 36, color: plugin.accentColor.withAlpha(150)),
          const SizedBox(height: 10),
          Text(
            panel.title.isNotEmpty ? panel.title : 'Custom JS Widget',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            'App ID: $widgetId',
            style: TextStyle(color: colors.textPrimary.withAlpha(96), fontSize: 10),
          ),
          const SizedBox(height: 16),
          // Decorative mock canvas dashboard element
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildMockWidgetMetric(context, '78%', 'CPU', colors.accentBlue),
              const SizedBox(width: 8),
              _buildMockWidgetMetric(context, '4.2 GB', 'MEM', colors.accentGreen),
              const SizedBox(width: 8),
              _buildMockWidgetMetric(context, '99.9%', 'UPTIME', colors.accentOrange),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _buildMockWidgetMetric(
  BuildContext context,
  String val,
  String label,
  Color color,
) {
  final colors = context.appColors;
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: colors.border, width: 0.5),
    ),
    child: Column(
      children: [
        Text(
          val,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: colors.textPrimary.withAlpha(96), fontSize: 7),
        ),
      ],
    ),
  );
}

Widget _buildMockRunRow(
  BuildContext context,
  BoardPanelPlugin plugin,
  String name,
  String status,
  String cmd,
) {
  final colors = context.appColors;
  final isActive = status == 'active';
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 4),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: colors.surface,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(
        color: isActive ? plugin.accentColor.withAlpha(100) : colors.border,
        width: isActive ? 1 : 0.5,
      ),
    ),
    child: Row(
      children: [
        Icon(
          isActive ? Icons.stop_circle_outlined : Icons.play_circle_outline,
          size: 16,
          color: isActive ? colors.statusError : plugin.accentColor,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(
                cmd,
                style: TextStyle(
                  color: colors.textPrimary.withAlpha(96),
                  fontSize: 8,
                  fontFamily: 'JetBrainsMono',
                ),
              ),
            ],
          ),
        ),
        if (isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: plugin.accentColor.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              'RUNNING',
              style: TextStyle(color: plugin.accentColor, fontSize: 7, fontWeight: FontWeight.bold),
            ),
          ),
      ],
    ),
  );
}

class _PulsingCursor extends StatefulWidget {
  const _PulsingCursor();
  @override
  State<_PulsingCursor> createState() => _PulsingCursorState();
}

class _PulsingCursorState extends State<_PulsingCursor> with SingleTickerProviderStateMixin {
  late AnimationController _anim;
  @override
  void initState() {
    super.initState();
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 500))..repeat(reverse: true);
  }
  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) => Opacity(
        opacity: _anim.value > 0.5 ? 1.0 : 0.0,
        child: Container(
          width: 6,
          height: 11,
          color: colors.terminalPrompt,
        ),
      ),
    );
  }
}

class _OffscreenPanelCard extends StatelessWidget {
  const _OffscreenPanelCard({required this.panel});

  final BoardPanelInstance panel;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return BoardPanelChrome(
      panel: panel,
      colors: colors,
      clipContent: true,
      content: BoardOverviewPanelContent(
        panel: panel,
        headerHeight: 44.0,
      ),
    );
  }
}
