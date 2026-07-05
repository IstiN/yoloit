import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

final _customWidgetDarkFallbackColors = AppColorScheme.fromAccent(
  Colors.indigo,
);

/// Web stub for the custom widget panel.
///
/// Keeps the same metadata and type id so existing boards deserialize; the
/// content renders a placeholder explaining that native JS widget execution
/// requires the desktop app.
class CustomWidgetPlugin extends BoardPanelPlugin {
  const CustomWidgetPlugin();

  static const String kTypeId = 'board.widget.custom';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Custom Widget';

  @override
  IconData get icon => Icons.widgets_outlined;

  @override
  Color get accentColor => _customWidgetDarkFallbackColors.primary;

  @override
  Size get defaultSize => const Size(360, 420);

  @override
  Map<String, dynamic> get initialState => {
    'widgetId': '',
    'config': <String, dynamic>{},
  };

  @override
  bool get supportsHeadlessRender => false;

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
        PlatformCapability.filesystem,
        PlatformCapability.processes,
        PlatformCapability.secureStorage,
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
