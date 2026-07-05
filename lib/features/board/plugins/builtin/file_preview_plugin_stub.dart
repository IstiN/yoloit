import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

final _filePreviewDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Web stub for the file preview panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that local file preview requires
/// the desktop app.
class FilePreviewPlugin extends BoardPanelPlugin {
  const FilePreviewPlugin();

  static const String kTypeId = 'board.file.preview';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'File Preview';

  @override
  IconData get icon => Icons.image_outlined;

  @override
  Color get accentColor => _filePreviewDefaultColors.primary;

  @override
  Size get defaultSize => const Size(460, 380);

  @override
  Map<String, dynamic> get initialState => {'path': '', 'title': ''};

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
        PlatformCapability.filesystem,
        PlatformCapability.processes,
        PlatformCapability.nativeMediaPlayback,
      };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return buildUnsupportedPanel();
  }
}
