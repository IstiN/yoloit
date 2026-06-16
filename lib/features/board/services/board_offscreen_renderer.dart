import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';

/// Renders a [BoardDocument] to a PNG image offscreen, without needing the
/// board to be mounted in the live widget tree.
///
/// Works like Flutter golden tests: creates an isolated [BuildOwner] +
/// [PipelineOwner] + [RenderView], builds the preview widget tree, lays it
/// out, paints it, and captures via [RenderRepaintBoundary.toImage].
///
/// No board switching is required — each board is rendered independently
/// from its data model, avoiding JSC crashes and UI flicker.
class BoardOffscreenRenderer {
  BoardOffscreenRenderer._();
  static final BoardOffscreenRenderer instance = BoardOffscreenRenderer._();

  /// Render [board] to PNG at the given [size] and [pixelRatio].
  ///
  /// Returns null if the board has no visible panels or rendering fails.
  Future<Uint8List?> renderBoard(
    BoardDocument board, {
    Size size = const Size(1400, 900),
    double pixelRatio = 1.5,
  }) async {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return null;
    final theme = ThemeManager.instance.theme;
    final colors =
        theme.extension<AppColorScheme>() ??
        AppColorScheme.fromAccent(Colors.deepPurple);

    // Headless BoardCubit: pre-populated with this board's data so plugins
    // that call context.read<BoardCubit>() get a valid, isolated instance
    // rather than throwing ProviderNotFoundException.
    final headlessCubit = _HeadlessBoardCubit(board);

    // ErrorWidget.builder acts as a last-resort safety net for any Dart-level
    // render error not covered by headless providers (e.g. plugin-specific
    // state that isn't injected yet). The panel shows a broken-image icon and
    // the error is logged; the rest of the board still renders.
    return _withErrorBuilder(
      colors: colors,
      cubit: headlessCubit,
      errorMessage: 'render failed',
      action: () => _renderWidgetToImage(
        _buildBoardPreview(board, headlessCubit, theme, colors),
        size,
        pixelRatio,
      ),
    );
  }

  /// Render a single [panel] from [board] to PNG at its native size.
  ///
  /// Returns null if rendering fails.
  Future<Uint8List?> renderPanel(
    BoardDocument board,
    BoardPanelInstance panel, {
    double pixelRatio = 2.0,
  }) async {
    final theme = ThemeManager.instance.theme;
    final colors =
        theme.extension<AppColorScheme>() ??
        AppColorScheme.fromAccent(Colors.deepPurple);

    final headlessCubit = _HeadlessBoardCubit(board);

    final panelSize = Size(
      panel.bounds.width.clamp(60.0, 4000.0),
      panel.bounds.height.clamp(60.0, 4000.0),
    );
    return _withErrorBuilder(
      colors: colors,
      cubit: headlessCubit,
      errorMessage: 'panel render failed',
      action: () => _renderWidgetToImage(
        _buildPanelPreview(board, panel, headlessCubit, theme, colors),
        panelSize,
        pixelRatio,
      ),
    );
  }

  Widget _buildPanelPreview(
    BoardDocument board,
    BoardPanelInstance panel,
    BoardCubit cubit,
    ThemeData theme,
    AppColorScheme colors,
  ) {
    return _wrapHeadless(
      cubit: cubit,
      mediaQueryData: MediaQueryData(
        size: Size(
          panel.bounds.width.clamp(60.0, 4000.0),
          panel.bounds.height.clamp(60.0, 4000.0),
        ),
      ),
      theme: theme,
      colors: colors,
      child: _OffscreenSinglePanel(
        panel: panel,
        colors: colors,
      ),
    );
  }

  Widget _buildBoardPreview(
    BoardDocument board,
    BoardCubit cubit,
    ThemeData theme,
    AppColorScheme colors,
  ) {
    // BlocProvider.value injects headless implementations so all plugins that
    // call context.read<BoardCubit>() receive a properly populated instance.
    // Use explicit MediaQuery/Theme (not MaterialApp) — isolated BuildOwner
    // has no View ancestor, so MaterialApp's ScaffoldMessenger breaks.
    // Panel-level Material + TooltipVisibility is applied in
    // [BoardOverviewPanelContent] via [_PreviewSafePanelShell].
    return _wrapHeadless(
      cubit: cubit,
      mediaQueryData: const MediaQueryData(size: Size(1400, 900)),
      theme: theme,
      colors: colors,
      child: ColoredBox(
        color: colors.background,
        child: BoardCanvasPreview(
          board: board,
          useViewport: true,
        ),
      ),
    );
  }

  Future<T?> _withErrorBuilder<T>({
    required AppColorScheme colors,
    required BoardCubit cubit,
    required String errorMessage,
    required Future<T?> Function() action,
  }) async {
    final originalErrorBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      assert(() {
        debugPrint(
        '[BoardOffscreenRenderer] panel render error: ${details.exception}',
      );
        return true;
      }());
      return ColoredBox(
        color: colors.border.withAlpha(32),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 20,
            color: colors.textMuted.withAlpha(128),
          ),
        ),
      );
    };

    try {
      return await action();
    } catch (e, st) {
      assert(() { debugPrint('[BoardOffscreenRenderer] $errorMessage: $e'); return true; }());
      debugPrintStack(stackTrace: st);
      return null;
    } finally {
      ErrorWidget.builder = originalErrorBuilder;
      cubit.close();
    }
  }

  Widget _wrapHeadless({
    required BoardCubit cubit,
    required MediaQueryData mediaQueryData,
    required ThemeData theme,
    required AppColorScheme colors,
    required Widget child,
  }) {
    return BlocProvider<BoardCubit>.value(
      value: cubit,
      child: Localizations(
        locale: const Locale('en', 'US'),
        delegates: [
          DefaultMaterialLocalizations.delegate,
          DefaultWidgetsLocalizations.delegate,
        ],
        child: MediaQuery(
          data: mediaQueryData,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: ScrollConfiguration(
              behavior: const HeadlessScrollBehavior(),
              child: Theme(
                data: theme,
                child: DefaultTextStyle(
                  style: TextStyle(color: colors.textPrimary, fontSize: 12),
                  child: IconTheme(
                    data: IconThemeData(
                      color: colors.textSecondary,
                      size: 14,
                    ),
                    child: child,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Render a widget to PNG bytes using an offscreen pipeline.
  Future<Uint8List?> _renderWidgetToImage(
    Widget widget,
    Size size,
    double pixelRatio,
  ) async {
    final repaintBoundary = RenderRepaintBoundary();

    // RenderView needs a FlutterView.
    final view = WidgetsBinding.instance.platformDispatcher.views.first;

    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(
        alignment: Alignment.center,
        child: repaintBoundary,
      ),
    );
    renderView.configuration = ViewConfiguration(
      physicalConstraints: BoxConstraints.tight(size * pixelRatio),
      logicalConstraints: BoxConstraints.tight(size),
      devicePixelRatio: pixelRatio,
    );

    final pipelineOwner = PipelineOwner()..rootNode = renderView;
    renderView.prepareInitialFrame();

    final buildOwner = BuildOwner(focusManager: FocusManager());
    final rootElement = RenderObjectToWidgetAdapter<RenderBox>(
      container: repaintBoundary,
      child: ConstrainedBox(
        constraints: BoxConstraints.tight(size),
        child: widget,
      ),
    ).attachToRenderTree(buildOwner);

    // Smart Adaptive Polling with 200ms Debounce: flushes dirty layouts and
    // processes build scopes every 50ms until the active task registry remains
    // completely empty for 4 consecutive event-loop turns (200ms). This prevents
    // sequential asynchronous tasks from being skipped during phase transitions.
    final watch = Stopwatch()..start();
    var emptyTurns = 0;

    while (watch.elapsedMilliseconds < 15000) {
      buildOwner.buildScope(rootElement);
      pipelineOwner.flushLayout();

      await Future<void>.delayed(const Duration(milliseconds: 50));

      if (HeadlessRenderRegistry.activeTasks.isEmpty) {
        emptyTurns++;
        if (emptyTurns >= 4) {
          break;
        }
      } else {
        emptyTurns = 0;
      }
    }

    // Final composite and paint pass immediately before capture. The adaptive
    // polling above already debounced 200ms after the last active task, which
    // is enough time for short fade-in transitions and image decoders to settle
    // without an artificial fixed delay.
    buildOwner.buildScope(rootElement);
    pipelineOwner.flushLayout();
    pipelineOwner.flushCompositingBits();
    pipelineOwner.flushPaint();

    // Capture.
    final image = await repaintBoundary.toImage(pixelRatio: pixelRatio);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    // Clean up.
    buildOwner.finalizeTree();

    return byteData?.buffer.asUint8List();
  }
}

/// A headless [BoardCubit] pre-populated with a single [BoardDocument].
///
/// Injected by [BoardOffscreenRenderer] so plugins that call
/// `context.read<BoardCubit>()` during offscreen rendering receive a valid,
/// fully-loaded state instead of throwing [ProviderNotFoundException].
///
/// All mutating methods are intentionally no-ops — the headless instance is
/// read-only and isolated from SharedPreferences / disk I/O.
class _HeadlessBoardCubit extends BoardCubit {
  _HeadlessBoardCubit(BoardDocument board) : super() {
    emit(BoardState(boards: [board], activeBoardId: board.id, isLoaded: true));
  }

  // Prevent any async side-effects (disk writes, network) during headless render.
  @override
  Future<void> load() async {}
}

/// Renders a single panel with its header bar at full (1:1) scale for
/// panel-level screenshots.
class _OffscreenSinglePanel extends StatelessWidget {
  const _OffscreenSinglePanel({
    required this.panel,
    required this.colors,
  });

  final BoardPanelInstance panel;
  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final accent = panel.color;
    final panelFill =
        accent == null
            ? colors.surface
            : Color.lerp(colors.surface, accent, 0.12) ?? colors.surface;
    final panelHeaderFill =
        accent == null
            ? colors.surfaceElevated
            : Color.lerp(colors.surfaceElevated, accent, 0.18) ??
                colors.surfaceElevated;
    final borderColor =
        accent == null
            ? colors.border
            : Color.lerp(colors.border, accent, 0.65) ?? colors.border;

    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type) ??
        BoardPluginRegistry.instance.fallback;

    return Material(
      type: MaterialType.transparency,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: panelFill,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 44,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: panelHeaderFill,
                  border: Border(
                    bottom: BorderSide(color: colors.divider, width: 1.0),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      plugin.icon,
                      size: 16,
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withAlpha(180),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        panel.title,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: BoardOverviewPanelContent(
                  panel: panel,
                  headerHeight: 44.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A global, lightweight registry for tracking active asynchronous tasks
/// (like Mermaid rendering and Custom JS Widget loads) during offscreen
/// screenshot captures.
class HeadlessRenderRegistry {
  HeadlessRenderRegistry._();
  static final Set<String> activeTasks = {};
}

/// A global custom scroll behavior for the headless/offscreen renderer.
class HeadlessScrollBehavior extends ScrollBehavior {
  const HeadlessScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const HeadlessScrollPhysics();
  }
}

/// A custom ScrollPhysics that overrides [recommendDeferredLoading] to bypass
/// the standard Flutter [View.of] lookup, avoiding headless runtime exceptions.
class HeadlessScrollPhysics extends ScrollPhysics {
  const HeadlessScrollPhysics({super.parent});

  @override
  HeadlessScrollPhysics applyTo(ScrollPhysics? ancestor) {
    return HeadlessScrollPhysics(parent: buildParent(ancestor));
  }

  @override
  bool recommendDeferredLoading(
    double velocity,
    dynamic metrics,
    BuildContext context,
  ) {
    return false; // Bypass View.of() completely!
  }
}
