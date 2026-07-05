import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

/// Web stub for the file tree panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that local file system browsing
/// requires the desktop app.
class FileTreePlugin extends BoardPanelPlugin {
  const FileTreePlugin();

  static const String kTypeId = 'board.filetree';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'File Tree';

  @override
  IconData get icon => Icons.account_tree_outlined;

  @override
  Color get accentColor => const Color(0xFF64748B);

  @override
  Size get defaultSize => const Size(320, 500);

  @override
  Map<String, dynamic> get initialState => {
    'rootPath': '',
    'expandedDirs': <String>[],
    'selectedFile': '',
  };

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
