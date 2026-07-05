import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

final _diffPreviewDefaultColors = AppColorScheme.fromAccent(Colors.deepPurple);

/// Web stub for the diff preview panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that Git diff preview requires the
/// desktop app.
class DiffPreviewPlugin extends BoardPanelPlugin {
  const DiffPreviewPlugin();

  static const String kTypeId = 'board.diff.preview';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Diff Preview';

  @override
  IconData get icon => Icons.difference_outlined;

  @override
  Color get accentColor => _diffPreviewDefaultColors.accentBlue;

  @override
  Size get defaultSize => const Size(600, 500);

  @override
  Map<String, dynamic> get initialState => {
    'filePath': '',
    'rootPath': '',
    'title': '',
  };

  @override
  bool get showInCatalog => false;

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
        PlatformCapability.filesystem,
        PlatformCapability.processes,
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
