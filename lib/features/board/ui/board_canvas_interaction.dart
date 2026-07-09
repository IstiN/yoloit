import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:yoloit/features/board/ui/board_constants.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

@visibleForTesting
bool boardShouldRevertInteractionForCanvasLock({
  required bool interactionStartedLocked,
  required bool currentlyLocked,
  bool isScaleChanging = false,
}) {
  return interactionStartedLocked && currentlyLocked && !isScaleChanging;
}

bool isPointerOverScrollableCard(Offset position, int viewId) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(result, position, viewId);
  return result.path.any(
    (entry) => entry.target is RenderScrollableCardMarker,
  );
}

/// Returns a revert reason when the viewport transform should be rolled back.
String? boardViewportInteractionRevertReason({
  required double startScale,
  required double currentScale,
  required bool interactionStartedLocked,
}) {
  if (boardShouldRevertInteractionForCanvasLock(
    interactionStartedLocked: interactionStartedLocked,
    currentlyLocked: CanvasInteractionLock.instance.isLocked,
    isScaleChanging: (currentScale - startScale).abs() > 0.01,
  )) {
    return 'canvasLock';
  }
  return null;
}

double boardEdgePanStep(double position, double extent) {
  if (extent <= 0) return 0;
  if (position < edgePanZone) {
    final t = ((edgePanZone - position) / edgePanZone).clamp(0.0, 1.0);
    return -edgePanMaxStep * Curves.easeOut.transform(t);
  }
  if (extent - position < edgePanZone) {
    final t = ((edgePanZone - (extent - position)) / edgePanZone).clamp(
      0.0,
      1.0,
    );
    return edgePanMaxStep * Curves.easeOut.transform(t);
  }
  return 0;
}
