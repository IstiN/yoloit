import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'package:yoloit/core/theme/app_color_scheme.dart';
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

    // Override ErrorWidget.builder so that individual panels that crash
    // (e.g. BLoC not available headless, native PTY, WebView) are replaced
    // with a grey placeholder and their errors are logged — the rest of the
    // board still renders correctly.
    final originalErrorBuilder = ErrorWidget.builder;
    ErrorWidget.builder = (FlutterErrorDetails details) {
      debugPrint(
        '[BoardOffscreenRenderer] panel render error: ${details.exception}',
      );
      return ColoredBox(
        color: const Color(0x20808080),
        child: const Center(
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
        _buildBoardPreview(board),
        size,
        pixelRatio,
      );
    } catch (e, st) {
      debugPrint('[BoardOffscreenRenderer] render failed: $e');
      debugPrintStack(stackTrace: st);
      return null;
    } finally {
      ErrorWidget.builder = originalErrorBuilder;
    }
  }

  Widget _buildBoardPreview(BoardDocument board) {
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

    return MediaQuery(
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
