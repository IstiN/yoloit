import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/files_plugin_base.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

/// Web stub for the files panel.
class FilesPlugin extends FilesPluginBase {
  const FilesPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
