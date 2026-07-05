import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin_base.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

/// Web stub for the YoLo Assistant panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that the AI assistant requires the
/// desktop app.
class YoloAssistantPlugin extends YoloAssistantPluginBase {
  const YoloAssistantPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
