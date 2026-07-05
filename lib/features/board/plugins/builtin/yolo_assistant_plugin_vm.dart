import 'package:flutter/material.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin_base.dart';

/// Board panel plugin for the YoLo Assistant — an AI chat with voice mode.
class YoloAssistantPlugin extends YoloAssistantPluginBase {
  const YoloAssistantPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return YoloAssistantWidget(
      panel: panel,
      onUpdateState: renderContext.onUpdateState,
    );
  }
}
