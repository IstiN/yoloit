import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// No-op web placeholder for WebView overlays.
///
/// The web build renders webpage panels inline with an iframe, so no native
/// platform-view overlay layer is needed.
// jscpd:ignore-start
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
// jscpd:ignore-end

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
