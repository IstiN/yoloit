import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

final _filePreviewDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Shared metadata for the file preview panel plugin.
abstract class FilePreviewPluginBase extends BoardPanelPluginBase {
  const FilePreviewPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'File Preview',
        icon: Icons.image_outlined,
        defaultSize: const Size(460, 380),
        initialState: const {'path': '', 'title': ''},
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
          PlatformCapability.nativeMediaPlayback,
        },
      );

  static const String kTypeId = 'board.file.preview';

  @override
  Color get accentColor => _filePreviewDefaultColors.primary;
}
