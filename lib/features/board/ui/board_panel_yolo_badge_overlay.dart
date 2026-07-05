import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin_base.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_layout.dart';

/// YoLo edge badge rendered above resize handles so both stay clickable.
class BoardPanelYoloBadgeOverlay extends StatelessWidget {
  const BoardPanelYoloBadgeOverlay({
    super.key,
    required this.panel,
    required this.canvasOrigin,
    required this.capturingScreenshot,
    required this.connectMode,
    required this.selected,
  });

  final BoardPanelInstance panel;
  final Offset canvasOrigin;
  final bool capturingScreenshot;
  final bool connectMode;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (capturingScreenshot ||
        connectMode ||
        panel.type == YoloAssistantPluginBase.kTypeId) {
      return const SizedBox.shrink();
    }

    final focusedPanelId = context.select<BoardCubit, String?>(
      (cubit) => cubit.state.activeBoard?.viewport.focusedPanelId,
    );
    if (panel.id != focusedPanelId) {
      return const SizedBox.shrink();
    }

    final yoloAssistantOpen = context.select<BoardCubit, bool>(
      (cubit) => cubit.state.yoloAssistantAnchorPanelId == panel.id,
    );
    final triggerHeight = YoloAnchoredAssistantLayout.triggerHeight(panel);

    return Positioned(
      left: canvasOrigin.dx + panel.bounds.x + panel.bounds.width - 2,
      top: canvasOrigin.dy + YoloAnchoredAssistantLayout.triggerTopY(panel),
      width:
          yoloAssistantOpen
              ? PanelYoloAssistantBadge.badgeWidth
              : PanelYoloAssistantBadge.hitWidth,
      height: triggerHeight,
      child: PanelYoloAssistantBadge(
        targetPanel: panel,
        assistantOpen: yoloAssistantOpen,
        highlighted: selected || yoloAssistantOpen,
      ),
    );
  }
}
