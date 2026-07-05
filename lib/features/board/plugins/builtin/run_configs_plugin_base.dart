import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

/// Shared metadata for the Run Configs panel plugin.
abstract class RunConfigsPluginBase extends BoardPanelPluginBase {
  const RunConfigsPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'Run Configs',
        icon: Icons.play_circle_outline,
        defaultSize: const Size(600, 400),
        initialState: const {},
        supportsHeadlessRender: false,
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.run_configs';

  @override
  Color get accentColor => const Color(0xFF22C55E);
}

/// Shared metadata for the compact Run panel plugin.
abstract class RunPluginBase extends BoardPanelPluginBase {
  const RunPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'Run',
        icon: Icons.play_arrow_rounded,
        defaultSize: const Size(560, 360),
        initialState: const {
          'group': 'default',
          'activeSessionId': null,
        },
        showInCatalog: false,
        supportsHeadlessRender: false,
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.run';

  @override
  Color get accentColor => const Color(0xFF22C55E);
}
