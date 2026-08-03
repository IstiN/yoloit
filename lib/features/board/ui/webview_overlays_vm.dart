import 'dart:async';

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

class WebViewOverlays extends StatefulWidget {
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

  @override
  State<WebViewOverlays> createState() => _WebViewOverlaysState();
}

class _WebViewOverlaysState extends State<WebViewOverlays> {
  /// Header (44) + URL bar (36) + divider (1) = content starts at 81px.
  static const double _contentOffsetY = 81.0;
  static const _settleDelay = Duration(milliseconds: 120);

  late Matrix4 _matrix;
  Timer? _settleTimer;
  bool _isSettling = false;

  @override
  void initState() {
    super.initState();
    _matrix = widget.transformController.value;
    widget.transformController.addListener(_onTransformChanged);
  }

  @override
  void didUpdateWidget(WebViewOverlays oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.transformController != oldWidget.transformController) {
      oldWidget.transformController.removeListener(_onTransformChanged);
      widget.transformController.addListener(_onTransformChanged);
      _matrix = widget.transformController.value;
    }
  }

  @override
  void dispose() {
    widget.transformController.removeListener(_onTransformChanged);
    _settleTimer?.cancel();
    super.dispose();
  }

  void _onTransformChanged() {
    // While the board is still moving (inertia, fling, etc.), hide overlays
    // and wait until the matrix settles. Repositioning native platform views
    // every frame is expensive and causes GPU overhead.
    _settleTimer?.cancel();
    if (!_isSettling) {
      setState(() => _isSettling = true);
    }
    _settleTimer = Timer(_settleDelay, () {
      if (!mounted) return;
      setState(() {
        _matrix = widget.transformController.value;
        _isSettling = false;
      });
    });
  }


  Rect? _screenRect(BoardPanelInstance panel, Matrix4 matrix, double scale) {
    final canvasPos = Offset(
      panel.bounds.x + widget.canvasOrigin.dx,
      panel.bounds.y + widget.canvasOrigin.dy + _contentOffsetY,
    );
    final screenPos = MatrixUtils.transformPoint(matrix, canvasPos);
    final w = panel.bounds.width * scale;
    final h = (panel.bounds.height - _contentOffsetY) * scale;
    if (w < 1 || h < 1) return null;
    return Rect.fromLTWH(screenPos.dx, screenPos.dy, w, h);
  }

  Widget _webViewOverlay(
    BuildContext context, {
    required String panelId,
    required Rect rect,
    required double scale,
    required WebViewController ctrl,
    required Color backgroundColor,
    List<Widget> extraChildren = const [],
  }) {
    return Positioned(
      key: ValueKey(panelId),
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(16 * scale),
            bottomRight: Radius.circular(16 * scale),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              ColoredBox(color: backgroundColor),
              WebViewWidget(controller: ctrl),
              _loadingOverlay(context, panelId),
              ...extraChildren,
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingOverlay(BuildContext context, String panelId) {
    return ValueListenableBuilder<bool>(
      valueListenable:
          WebpagePluginBase.pageLoading[panelId] ?? ValueNotifier<bool>(false),
      builder: (_, isLoading, _) {
        if (!isLoading) return const SizedBox.shrink();
        return ColoredBox(
          color: context.appColors.surfaceHighlight,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final webPanels = _visibleWebPanels();

    if (webPanels.isEmpty) return const SizedBox.shrink();

    // During active pinch-to-zoom / pan (or while the transform is still
    // settling after a gesture), hide overlays to avoid visual desync and to
    // skip expensive per-frame repositioning of native platform views.
    if (widget.isInteracting || _isSettling) return const SizedBox.shrink();

    return LayoutBuilder(
      builder:
          (context, constraints) => _buildOverlays(context, webPanels, constraints),
    );
  }

  List<BoardPanelInstance> _visibleWebPanels() {
    return widget.panels
        .where(
          (p) =>
              p.type == WebpagePluginBase.kTypeId &&
              !p.hidden &&
              WebpagePluginBase.controllers.containsKey(p.id),
        )
        .toList();
  }

  Widget _buildOverlays(
    BuildContext context,
    List<BoardPanelInstance> webPanels,
    BoxConstraints constraints,
  ) {
    final viewportRect = Rect.fromLTWH(
      0,
      0,
      constraints.maxWidth,
      constraints.maxHeight,
    );

    final matrix = _matrix;
    final scale = matrixScaleOf(matrix);

    // Apply CSS zoom = boardScale so pages use desktop layout widths.
    // pageZoom is NOT used — it shrinks content visually without
    // changing window.innerWidth.
    final children = _unfocusedOverlays(
      context,
      webPanels,
      viewportRect,
      matrix,
      scale,
    );
    final focused = _focusedOverlay(context, webPanels, matrix, scale);
    if (focused != null) children.add(focused);

    if (children.isEmpty) return const SizedBox.shrink();
    return Stack(children: children);
  }

  /// ── 1. Unfocused WebView overlays (bottom z-order) ──
  List<Widget> _unfocusedOverlays(
    BuildContext context,
    List<BoardPanelInstance> webPanels,
    Rect viewportRect,
    Matrix4 matrix,
    double scale,
  ) {
    final children = <Widget>[];
    for (final panel in webPanels) {
      if (panel.id == widget.focusedPanelId) continue;
      final rect = _screenRect(panel, matrix, scale);
      if (rect == null) continue;
      // Viewport culling — skip off-screen panels.
      if (!rect.overlaps(viewportRect)) continue;

      final ctrl = WebpagePluginBase.controllers[panel.id]! as WebViewController;

      // pageZoom in Swift handles viewport width. No CSS zoom needed.
      if (!WebpagePluginBase.pendingCssZoom.containsKey(panel.id)) {
        WebpagePluginBase.pendingCssZoom[panel.id] = 1.0;
      }

      children.add(
        _webViewOverlay(
          context,
          panelId: 'wv-${panel.id}',
          rect: rect,
          scale: scale,
          ctrl: ctrl,
          backgroundColor: context.appColors.background,
          extraChildren: [
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
      );
    }
    return children;
  }

  /// ── 2. Focused WebView overlay (top z-order, full interaction) ──
  /// No full-screen background — the canvas Listener inside
  /// InteractiveViewer handles unfocusing when clicking empty space.
  Widget? _focusedOverlay(
    BuildContext context,
    List<BoardPanelInstance> webPanels,
    Matrix4 matrix,
    double scale,
  ) {
    final focusedPanel =
        webPanels.where((p) => p.id == widget.focusedPanelId).firstOrNull;
    if (focusedPanel == null) return null;
    final rect = _screenRect(focusedPanel, matrix, scale);
    if (rect == null) return null;

    final ctrl =
        WebpagePluginBase.controllers[focusedPanel.id]! as WebViewController;

    // pageZoom in Swift handles viewport width via frame observer.
    if (!WebpagePluginBase.pendingCssZoom.containsKey(focusedPanel.id)) {
      WebpagePluginBase.pendingCssZoom[focusedPanel.id] = 1.0;
    }

    return _webViewOverlay(
      context,
      panelId: 'wv-focused-${focusedPanel.id}',
      rect: rect,
      scale: scale,
      ctrl: ctrl,
      backgroundColor: context.appColors.surface,
    );
  }
}
