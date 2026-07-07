import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_base.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

/// Web stub for the custom widget panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that native JS widget execution
/// requires the desktop app.
class CustomWidgetPlugin extends CustomWidgetPluginBase {
  const CustomWidgetPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
