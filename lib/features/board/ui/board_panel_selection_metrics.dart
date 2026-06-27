import 'dart:ui';

import 'package:yoloit/features/board/model/board_models.dart';

/// Shared selection chrome geometry for [BoardPanelCard] and floating overlays.
class BoardPanelSelectionMetrics {
  const BoardPanelSelectionMetrics._();

  static const double sideGutter = 18;
  static const double topGutter = 62;
  static const double bottomGutter = 18;
  static const double handleInset = 12;
  static const double floatingChromeHeight = 38;
  static const double floatingChromeGap = 8;

  /// Top-left origin for [StickyNoteChrome] in canvas coordinates.
  ///
  /// [panel.bounds.y] is already the host content top — do not subtract
  /// [topGutter] again (that only exists inside [BoardPanelCard]'s wrapper).
  static Offset floatingChromeOrigin(
    BoardPanelInstance panel,
    Offset canvasOrigin,
  ) {
    return Offset(
      panel.bounds.x + canvasOrigin.dx,
      panel.bounds.y +
          canvasOrigin.dy -
          floatingChromeHeight -
          floatingChromeGap,
    );
  }
}
