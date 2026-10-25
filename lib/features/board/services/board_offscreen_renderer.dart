import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';
import 'package:yoloit/features/board/ui/widgets/board_panel_chrome.dart';

/// Cooperative cancellation token for long-running offscreen renders.
class CancelToken {
  bool _cancelled = false;
  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled;
}

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

  /// Logical size for boards-overview card thumbnails (matches ~1.55 card AR).
  static const Size overviewPreviewSize = Size(620, 400);

  /// Hard cap on the physical pixel count of a captured image: 2^24 ≈ 16.7M
  /// pixels ≈ 64 MiB at RGBA8888. Without this, a 4000x4000 logical panel at
  /// pixelRatio 2.0 would allocate a single 8000x8000 ui.Image (~244 MiB).
  static const int maxCapturePhysicalPixels = 16777216;

  /// Captures a [RenderRepaintBoundary] to a [ui.Image]. Indirection seam so
  /// tests can inject images and assert disposal on the success/error paths.
  @visibleForTesting
  static Future<ui.Image> Function(
    RenderRepaintBoundary boundary, {
    required double pixelRatio,
  }) imageCapturer =
      (boundary, {required pixelRatio}) =>
          boundary.toImage(pixelRatio: pixelRatio);

  /// Encodes a captured [ui.Image] to bytes. Indirection seam so tests can
  /// force the error path between capture and disposal.
  @visibleForTesting
  static Future<ByteData?> Function(ui.Image image, ui.ImageByteFormat format)
  imageEncoder = (image, format) => image.toByteData(format: format);

  /// Sleeps between capture-loop polls. Indirection seam so tests can drive
  /// the loop with a fake clock (see [pollElapsedMsOverride]) without real
  /// wall-time delays.
  @visibleForTesting
  static Future<void> Function(Duration duration) pollSleeper =
      (duration) => Future<void>.delayed(duration);

  /// Overrides the capture loop's elapsed-time source (milliseconds). When
  /// null the loop uses a real [Stopwatch]. Tests inject a fake clock that
  /// advances together with [pollSleeper] so 15s-timeout scenarios run
  /// instantly.
  @visibleForTesting
  static int Function()? pollElapsedMsOverride;

  /// Returns a (size, pixelRatio) pair whose physical pixel count never
  /// exceeds [maxCapturePhysicalPixels].
  ///
  /// Requests already within the cap are returned unchanged (small-size
  /// behavior stays byte-identical). Oversized requests first reduce
  /// [pixelRatio] (preferred, preserves logical layout); only when the ratio
  /// would fall below 1.0 are the logical dimensions shrunk at a 1.0 ratio.
  @visibleForTesting
  static ({Size size, double pixelRatio}) capCaptureSize(
    Size size,
    double pixelRatio,
  ) {
    final wPx = (size.width * pixelRatio).ceil();
    final hPx = (size.height * pixelRatio).ceil();
    if (wPx <= 0 || hPx <= 0 || wPx * hPx <= maxCapturePhysicalPixels) {
      return (size: size, pixelRatio: pixelRatio);
    }
    final scale = math.sqrt(maxCapturePhysicalPixels / (wPx * hPx));
    final reducedRatio = pixelRatio * scale;
    if (reducedRatio >= 1.0) {
      return (size: size, pixelRatio: reducedRatio);
    }
    // Even a 1.0 pixel ratio on the full logical size exceeds the cap —
    // clamp the logical dimensions instead (exactly hits the cap).
    return (size: size * reducedRatio, pixelRatio: 1.0);
  }

  /// Render a boards-overview thumbnail: always fits all panels, never viewport.
  Future<Uint8List?> renderBoardOverviewPreview(
    BoardDocument board, {
    CancelToken? cancelToken,
  }) {
    return renderBoard(
      board,
      size: overviewPreviewSize,
      pixelRatio: 1.0,
      useViewport: false,
      cancelToken: cancelToken,
    );
  }

  /// Render [board] to PNG at the given [size] and [pixelRatio].
  ///
  /// Returns null if the board has no visible panels or rendering fails.
  /// Pass [cancelToken] to abort early when the user switches boards or closes
  /// the overview, preventing wasted CPU cycles.
  ///
  /// When [useViewport] is `false` the renderer fits all panels into [size]
  /// regardless of the board's current viewport — useful for template previews.
  Future<Uint8List?> renderBoard(
    BoardDocument board, {
    Size size = const Size(1400, 900),
    double pixelRatio = 1.5,
    CancelToken? cancelToken,
    bool useViewport = true,
  }) async {
    final panels = board.panels.where((p) => !p.hidden).toList();
    final hasDrawings = board.drawings.any((d) => !d.hidden);
    if (panels.isEmpty && !hasDrawings) return null;
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
        _buildBoardPreview(
          board,
          headlessCubit,
          theme,
          colors,
          useViewport: useViewport,
        ),
        size,
        pixelRatio,
        cancelToken: cancelToken,
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
    CancelToken? cancelToken,
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
        cancelToken: cancelToken,
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
    AppColorScheme colors, {
    required bool useViewport,
  }) {
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
          useViewport: useViewport,
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
                    // Disable text selection in headless snapshots: SelectionArea
                    // registers async selection updates that can call
                    // findRenderObject() after the tree is finalized, causing
                    // "inactive element" exceptions.
                    child: SelectionContainer.disabled(child: child),
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
    double pixelRatio, {
    CancelToken? cancelToken,
  }) async {
    // Never allocate a physical image beyond the memory cap.
    final capped = capCaptureSize(size, pixelRatio);
    size = capped.size;
    pixelRatio = capped.pixelRatio;

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

    ui.Image? image;
    try {
      // Smart Adaptive Polling with 200ms Debounce and exponential backoff.
      //
      // Flushes dirty layouts and processes build scopes until the tasks that
      // belong to THIS capture have been quiet for 4 consecutive turns
      // (200ms). The poll interval doubles (50 -> 100 -> 200 -> 400ms cap)
      // whenever the active-task set is unchanged since the previous poll and
      // resets to 50ms on any change; a hard 15s timeout bounds the total
      // wait regardless.
      //
      // Tasks already running when the capture began belong to earlier work
      // (e.g. a task stuck from a previous capture): the start snapshot is
      // subtracted before evaluating the quiet condition, so such a task no
      // longer forces every later capture to burn the full 15s window. Tasks
      // registered DURING this capture (JS engine / Mermaid loads, including
      // sequential chains) are still waited on exactly as before.
      final tracker = CapturePollTracker(
        Set.of(HeadlessRenderRegistry.activeTasks),
      );
      final watch = Stopwatch()..start();
      int elapsedMs() =>
          pollElapsedMsOverride?.call() ?? watch.elapsedMilliseconds;

      while (elapsedMs() < CapturePollTracker.timeoutMs) {
        if (cancelToken?.isCancelled ?? false) {
          break;
        }
        buildOwner.buildScope(rootElement);
        pipelineOwner.flushLayout();

        await pollSleeper(tracker.interval);

        if (cancelToken?.isCancelled ?? false) {
          break;
        }

        if (tracker.recordObservation(
          Set.of(HeadlessRenderRegistry.activeTasks),
        )) {
          break;
        }
      }

      if (cancelToken?.isCancelled ?? false) {
        return null;
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
      image = await imageCapturer(repaintBoundary, pixelRatio: pixelRatio);
      final byteData = await imageEncoder(image, ui.ImageByteFormat.png);
      return byteData?.buffer.asUint8List();
    } finally {
      // Guarantee native-image disposal and tree finalization exactly once,
      // on success, cancellation, and error alike.
      image?.dispose();
      buildOwner.finalizeTree();
    }
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
    return BoardPanelChrome(
      panel: panel,
      colors: colors,
      clipContent: false,
      content: BoardOverviewPanelContent(
        panel: panel,
        headerHeight: 44.0,
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

/// Next poll interval for the offscreen capture loop: resets to
/// [CapturePollTracker.intervalStart] when the active-task set changed since
/// the previous poll, otherwise doubles up to
/// [CapturePollTracker.intervalCap].
@visibleForTesting
Duration nextPollInterval(Duration current, {required bool taskSetChanged}) {
  if (taskSetChanged) {
    return CapturePollTracker.intervalStart;
  }
  final doubled = current * 2;
  return doubled > CapturePollTracker.intervalCap
      ? CapturePollTracker.intervalCap
      : doubled;
}

/// Pure decision logic for the offscreen capture polling loop.
///
/// The loop polls [HeadlessRenderRegistry.activeTasks] until tasks that
/// belong to THIS capture (registered after [startSnapshot] was taken) have
/// been quiet for [quietTurnsRequired] consecutive turns, or the hard
/// [timeoutMs] fires. A task already running when the capture began belongs
/// to earlier work: it is part of [startSnapshot] and is subtracted before
/// evaluating the quiet condition, so it does not by itself keep this
/// capture waiting — mirroring how the loop already treats its own
/// completion.
@visibleForTesting
class CapturePollTracker {
  /// Initial poll interval on capture start and after any task-set change.
  static const Duration intervalStart = Duration(milliseconds: 50);

  /// Maximum poll interval while the active-task set stays unchanged.
  static const Duration intervalCap = Duration(milliseconds: 400);

  /// Consecutive quiet turns required before the capture proceeds (4 x 50ms
  /// start interval = 200ms debounce).
  static const int quietTurnsRequired = 4;

  /// Hard cap on total polling time, in milliseconds.
  static const int timeoutMs = 15000;

  /// Tasks active when this capture began — earlier work, not gating.
  final Set<String> startSnapshot;

  Duration _interval = intervalStart;
  int _quietTurns = 0;
  Set<String>? _previousTasks;

  CapturePollTracker(Set<String> startTasks)
      : startSnapshot = Set.unmodifiable(startTasks);

  /// Current poll interval for the next sleep.
  Duration get interval => _interval;

  /// Consecutive turns with no active task belonging to this capture.
  int get quietTurns => _quietTurns;

  /// The quiet window has been filled and the capture may proceed.
  bool get isQuietComplete => _quietTurns >= quietTurnsRequired;

  /// Records one poll observation of the current [activeTasks] set and
  /// advances the quiet-window and backoff bookkeeping. Returns
  /// [isQuietComplete] for the caller's exit check.
  bool recordObservation(Set<String> activeTasks) {
    final quiet = activeTasks.difference(startSnapshot).isEmpty;
    _quietTurns = quiet ? _quietTurns + 1 : 0;
    final changed =
        _previousTasks == null || !setEquals(activeTasks, _previousTasks);
    _interval = nextPollInterval(_interval, taskSetChanged: changed);
    _previousTasks = Set.of(activeTasks);
    return isQuietComplete;
  }
}
