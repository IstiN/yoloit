import 'dart:math' as math;
import 'dart:ui';

import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';

/// Computes board-space geometry for the YoLo assistant panel anchored to a host.
class YoloAnchoredAssistantLayout {
  const YoloAnchoredAssistantLayout._();

  static const double badgeInset = 2;
  static const double frameWidth = 1.5;
  static const double panelOverlap = 3;

  static const double preferredTabHeight = 120;

  static double triggerHeight(BoardPanelInstance anchor) {
    final panelHeight = anchor.bounds.height;
    if (panelHeight <= PanelYoloAssistantBadge.minTriggerHeight) {
      return PanelYoloAssistantBadge.minTriggerHeight;
    }
    return math.min(panelHeight, preferredTabHeight);
  }

  static double triggerTopY(BoardPanelInstance anchor) =>
      anchor.bounds.y + (anchor.bounds.height - triggerHeight(anchor)) / 2;

  static double badgeCenterY(BoardPanelInstance anchor) =>
      triggerTopY(anchor) + triggerHeight(anchor) / 2;

  static double badgeLeftX(BoardPanelInstance anchor) =>
      anchor.bounds.x + anchor.bounds.width - badgeInset;

  static double panelLeftX(BoardPanelInstance anchor) =>
      badgeLeftX(anchor) +
      PanelYoloAssistantBadge.badgeWidth -
      panelOverlap;

  /// Badge top in board space — unchanged when the chat panel opens.
  static double badgeTopY(BoardPanelInstance anchor) => triggerTopY(anchor);

  /// Final docked frame (t = 1).
  static BoardPanelBounds dockedPanelBounds(BoardPanelInstance anchor) {
    final panelHeight = PanelYoloAssistantBadge.expandedHeight;
    final centerY = badgeCenterY(anchor);
    return BoardPanelBounds(
      x: panelLeftX(anchor),
      y: centerY - panelHeight / 2,
      width: PanelYoloAssistantBadge.expandedWidth,
      height: panelHeight,
    );
  }

  /// Grows from badge center: height badge→full, width 0→full.
  static BoardPanelBounds animatedPanelBounds(
    BoardPanelInstance anchor,
    double t,
  ) {
    final centerY = badgeCenterY(anchor);
    final badgeH = triggerHeight(anchor);
    final fullH = PanelYoloAssistantBadge.expandedHeight;
    final fullW = PanelYoloAssistantBadge.expandedWidth;
    final height = lerpDouble(badgeH, fullH, t)!;
    final width = lerpDouble(0, fullW, t)!;
    return BoardPanelBounds(
      x: panelLeftX(anchor),
      y: centerY - height / 2,
      width: width,
      height: height,
    );
  }

  static double badgeTopInCardWrapper(
    BoardPanelInstance anchor, {
    required double selectionTopGutter,
  }) {
    return selectionTopGutter +
        (anchor.bounds.height - triggerHeight(anchor)) / 2;
  }
}
