import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
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
    Size size = const Size(960, 640),
    double pixelRatio = 1.5,
  }) async {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return null;

    // Headless BoardCubit: pre-populated with this board's data so plugins
    // that call context.read<BoardCubit>() get a valid, isolated instance
    // rather than throwing ProviderNotFoundException.
    final headlessCubit = _HeadlessBoardCubit(board);

    // ErrorWidget.builder acts as a last-resort safety net for any Dart-level
    // render error not covered by headless providers (e.g. plugin-specific
    // state that isn't injected yet). The panel shows a broken-image icon and
    // the error is logged; the rest of the board still renders.
    final originalErrorBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint(
        '[BoardOffscreenRenderer] panel render error: ${details.exception}',
      );
      return const ColoredBox(
        color: Color(0x20808080),
        child: Center(
          child: Icon(
            Icons.broken_image_outlined,
            size: 20,
            color: Color(0x80808080),
          ),
        ),
      );
    };

    try {
      return await _renderWidgetToImage(
        _buildBoardPreview(board, headlessCubit),
        size,
        pixelRatio,
      );
    } catch (e, st) {
      debugPrint('[BoardOffscreenRenderer] render failed: $e');
      debugPrintStack(stackTrace: st);
      return null;
    } finally {
      ErrorWidget.builder = originalErrorBuilder;
      headlessCubit.close();
    }
  }

  Widget _buildBoardPreview(BoardDocument board, BoardCubit cubit) {
    // Dark theme matching the app's look.
    final appColors = AppColorScheme.fromAccent(const Color(0xFF7C3AED));
    final theme = ThemeData.dark().copyWith(
      extensions: [appColors],
      colorScheme: const ColorScheme.dark(
        surface: Color(0xFF0F0F1A),
        onSurface: Color(0xFFE0E0F0),
        primary: Color(0xFF9D4EDD),
      ),
      textTheme: const TextTheme(
        bodySmall: TextStyle(color: Color(0xFF8888AA)),
      ),
      dividerColor: const Color(0xFF2A2A40),
    );

    // BlocProvider.value injects headless implementations so all plugins that
    // call context.read<BoardCubit>() receive a properly populated instance.
    // Add more providers here as new plugins gain BLoC/service dependencies.
    return BlocProvider<BoardCubit>.value(
      value: cubit,
      child: MediaQuery(
        data: const MediaQueryData(size: Size(960, 640)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Theme(
            data: theme,
            child: DefaultTextStyle(
              style: const TextStyle(
                color: Color(0xFFE0E0F0),
                fontSize: 12,
              ),
              child: IconTheme(
                data: const IconThemeData(color: Color(0xFF8888AA), size: 14),
                child: ColoredBox(
                  color: const Color(0xFF0F0F1A),
                  child: BoardOverviewPreview(board: board),
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

    // Build, layout, paint — all synchronous, no frame scheduling needed.
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
    emit(BoardState(
      boards: [board],
      activeBoardId: board.id,
      isLoaded: true,
    ));
  }

  // Prevent any async side-effects (disk writes, network) during headless render.
  @override
  Future<void> load() async {}
}
