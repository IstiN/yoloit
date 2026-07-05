import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin_base.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_widget.dart';

class BoardTerminalPanelPlugin extends BoardTerminalPanelPluginBase {
  const BoardTerminalPanelPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return BoardTerminalPanelWidget(
      panel: panel,
      onUpdateState: renderContext.onUpdateState,
      remoteInfo: renderContext.remoteInfo,
    );
  }
}
