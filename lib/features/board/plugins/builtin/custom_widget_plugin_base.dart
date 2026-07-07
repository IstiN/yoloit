import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

final _customWidgetDarkFallbackColors = AppColorScheme.fromAccent(
  Colors.indigo,
);

/// Shared metadata for the custom widget panel on VM and web stub.
abstract class CustomWidgetPluginBase extends BoardPanelPlugin {
  const CustomWidgetPluginBase();

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
}
