import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';

/// Exposes the active anchored YoLo chat controller to edge badges on panels.
class YoloAnchoredAssistantScope extends InheritedWidget {
  const YoloAnchoredAssistantScope({
    super.key,
    required this.anchorPanelId,
    required this.chatController,
    required super.child,
  });

  final String? anchorPanelId;
  final ChatPanelController? chatController;

  static YoloAnchoredAssistantScope? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<YoloAnchoredAssistantScope>();
  }

  static ChatPanelController? controllerFor(
    BuildContext context,
    String panelId,
  ) {
    final scope = maybeOf(context);
    if (scope == null || scope.anchorPanelId != panelId) return null;
    return scope.chatController;
  }

  @override
  bool updateShouldNotify(YoloAnchoredAssistantScope oldWidget) {
    return oldWidget.anchorPanelId != anchorPanelId ||
        oldWidget.chatController != chatController;
  }
}
