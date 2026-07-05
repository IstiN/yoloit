import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

/// Web stub for the declarative JSON UI panel.
class UiViewPlugin extends UiViewPluginBase {
  const UiViewPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }

  @override
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel) =>
      buildUnsupportedPanel();
}
