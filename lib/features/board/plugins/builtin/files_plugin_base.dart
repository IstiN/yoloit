import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

/// Shared metadata for the files panel plugin.
abstract class FilesPluginBase extends BoardPanelPluginBase {
  const FilesPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'Files',
        icon: Icons.attach_file_outlined,
        defaultSize: const Size(360, 320),
        initialState: const {'files': <Map<String, dynamic>>[]},
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.files';

  @override
  Color get accentColor => const Color(0xFFEC4899);
}
