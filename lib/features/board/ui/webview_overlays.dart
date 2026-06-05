import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin.dart';
import 'package:yoloit/features/board/ui/board_math.dart';

// ─────────────────────────────────────────────────────────────────────────────
// WebView overlays — renders live WebViews for ALL webpage panels OUTSIDE the
// InteractiveViewer's Transform widget, avoiding the fundamental coordinate
// mismatch between Flutter's transform and native macOS platform views.
//
// Unfocused panels: visible but input blocked (click → focus that panel).
// Focused panel:    full interaction, on top z-order.
// ─────────────────────────────────────────────────────────────────────────────

class WebViewOverlays extends StatelessWidget {
  const WebViewOverlays({
    super.key,
    required this.panels,
    required this.focusedPanelId,
    required this.transformController,
    required this.canvasOrigin,
    required this.isInteracting,
  });

  final List<BoardPanelInstance> panels;
  final String? focusedPanelId;
  final TransformationController transformController;
  final Offset canvasOrigin;
  final bool isInteracting;

  /// Header (44) + URL bar (36) + divider (1) = content starts at 81px.
  static const double _contentOffsetY = 81.0;

  Rect? _screenRect(BoardPanelInstance panel, Matrix4 matrix, double scale) {
    final canvasPos = Offset(
      panel.bounds.x + canvasOrigin.dx,
      panel.bounds.y + canvasOrigin.dy + _contentOffsetY,
    );
    final screenPos = MatrixUtils.transformPoint(matrix, canvasPos);
    final w = panel.bounds.width * scale;
    final h = (panel.bounds.height - _contentOffsetY) * scale;
    if (w < 1 || h < 1) return null;
    return Rect.fromLTWH(screenPos.dx, screenPos.dy, w, h);
  }

  @override
  Widget build(BuildContext context) {
    final webPanels =
        panels
            .where(
              (p) =>
                  p.type == WebpagePlugin.kTypeId &&
                  !p.hidden &&
                  WebpagePlugin.controllers.containsKey(p.id),
            )
            .toList();

    if (webPanels.isEmpty) return const SizedBox.shrink();

    // During active pinch-to-zoom / pan, hide overlays to avoid
    // visual desync — native NSView frame updates lag behind
    // the GPU-rendered InteractiveViewer transform.
    if (isInteracting) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportRect = Rect.fromLTWH(
          0,
          0,
          constraints.maxWidth,
          constraints.maxHeight,
        );

        return ValueListenableBuilder<Matrix4>(
          valueListenable: transformController,
          builder: (context, matrix, _) {
            final scale = matrixScaleOf(matrix);
            final children = <Widget>[];

            // Apply CSS zoom = boardScale so pages use desktop layout widths.
            // pageZoom is NOT used — it shrinks content visually without
            // changing window.innerWidth.

            // ── 1. Unfocused WebView overlays (bottom z-order) ──
            for (final panel in webPanels) {
              if (panel.id == focusedPanelId) continue;
              final rect = _screenRect(panel, matrix, scale);
              if (rect == null) continue;
              // Viewport culling — skip off-screen panels.
              if (!rect.overlaps(viewportRect)) continue;

              final ctrl = WebpagePlugin.controllers[panel.id]!;

              // pageZoom in Swift handles viewport width. No CSS zoom needed.
              if (!WebpagePlugin.pendingCssZoom.containsKey(panel.id)) {
                WebpagePlugin.pendingCssZoom[panel.id] = 1.0;
              }

              children.add(
                Positioned(
                  key: ValueKey('wv-${panel.id}'),
                  left: rect.left,
                  top: rect.top,
                  width: rect.width,
                  height: rect.height,
                  child: ClipRRect(
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(16 * scale),
                      bottomRight: Radius.circular(16 * scale),
                    ),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(color: context.appColors.background),
                        WebViewWidget(controller: ctrl),
                        // Loading overlay
                        ValueListenableBuilder<bool>(
                          valueListenable:
                              WebpagePlugin.pageLoading[panel.id] ??
                              ValueNotifier<bool>(false),
                          builder: (_, isLoading, __) {
                            if (!isLoading) return const SizedBox.shrink();
                            return ColoredBox(
                              color: context.appColors.surfaceHighlight,
                            );
                          },
                        ),
                        // Absorb clicks → focus this panel
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (kDebugMode) {
                              debugPrint(
                                '[BoardWebFocus] unfocused overlay tap -> focus panel=${panel.id}',
                              );
                            }
                            context.read<BoardCubit>().focusPanel(panel.id);
                            FocusManager.instance.primaryFocus?.unfocus();
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // ── 2. Focused WebView overlay (top z-order, full interaction) ──
            // No full-screen background — the canvas Listener inside
            // InteractiveViewer handles unfocusing when clicking empty space.
            final focusedPanel =
                webPanels.where((p) => p.id == focusedPanelId).firstOrNull;
            if (focusedPanel != null) {
              final rect = _screenRect(focusedPanel, matrix, scale);
              if (rect != null) {
                final ctrl = WebpagePlugin.controllers[focusedPanel.id]!;

                // pageZoom in Swift handles viewport width via frame observer.
                if (!WebpagePlugin.pendingCssZoom.containsKey(
                  focusedPanel.id,
                )) {
                  WebpagePlugin.pendingCssZoom[focusedPanel.id] = 1.0;
                }

                children.add(
                  Positioned(
                    key: ValueKey('wv-focused-${focusedPanel.id}'),
                    left: rect.left,
                    top: rect.top,
                    width: rect.width,
                    height: rect.height,
                    child: ClipRRect(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(16 * scale),
                        bottomRight: Radius.circular(16 * scale),
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ColoredBox(color: context.appColors.surface),
                          WebViewWidget(controller: ctrl),
                          // Loading overlay (navigation flash hide)
                          ValueListenableBuilder<bool>(
                            valueListenable:
                                WebpagePlugin.pageLoading[focusedPanel.id] ??
                                ValueNotifier<bool>(false),
                            builder: (_, isLoading, __) {
                              if (!isLoading) return const SizedBox.shrink();
                              return ColoredBox(
                                color: context.appColors.surfaceHighlight,
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }
            }

            if (children.isEmpty) return const SizedBox.shrink();
            return Stack(children: children);
          },
        );
      },
    );
  }
}
