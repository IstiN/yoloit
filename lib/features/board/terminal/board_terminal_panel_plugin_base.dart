import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

/// Shared metadata for the native terminal panel plugin.
abstract class BoardTerminalPanelPluginBase extends BoardPanelPluginBase {
  const BoardTerminalPanelPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'Terminal',
        icon: Icons.terminal,
        defaultSize: const Size(520, 360),
        initialState: const {
          'config': {
            'sessionId': '',
            'sessionName': '',
            'workingDir': '',
            'envGroupIds': <String>[],
          },
        },
        showInCatalog: false,
        supportsHeadlessRender: false,
        requiredCapabilities: const {
          PlatformCapability.nativeTerminal,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.terminal';

  @override
  Color get accentColor => const Color(0xFF22C55E);
}
