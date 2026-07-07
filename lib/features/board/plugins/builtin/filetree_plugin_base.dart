import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

final _fileTreeDefaultColors = AppColorScheme.fromAccent(Colors.blueGrey);

/// Shared metadata for the file tree panel plugin.
abstract class FileTreePluginBase extends BoardPanelPluginBase {
  const FileTreePluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'File Tree',
        icon: Icons.account_tree_outlined,
        defaultSize: const Size(320, 500),
        initialState: const {
          'rootPath': '',
          'expandedDirs': <String>[],
          'selectedFile': '',
        },
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.filetree';

  @override
  Color get accentColor => _fileTreeDefaultColors.primary;
}
