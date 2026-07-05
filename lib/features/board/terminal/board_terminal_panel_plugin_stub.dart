import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin_base.dart';

/// Web stub for the terminal panel.
class BoardTerminalPanelPlugin extends BoardTerminalPanelPluginBase {
  const BoardTerminalPanelPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
