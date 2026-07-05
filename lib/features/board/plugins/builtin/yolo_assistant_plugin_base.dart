import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/features/board/plugins/board_panel_plugin_base.dart';

/// Shared metadata for the YoLo Assistant panel plugin.
abstract class YoloAssistantPluginBase extends BoardPanelPluginBase {
  const YoloAssistantPluginBase()
    : super(
        typeId: kTypeId,
        displayName: 'YoLo Assistant',
        icon: Icons.auto_awesome,
        defaultSize: const Size(420, 560),
        initialState: const {
          'messages': <Map<String, dynamic>>[],
          'activeSkills': <String>['Terminal', 'Board Control', 'Web Search'],
          'mode': 'text',
          'isListening': false,
          'isSpeaking': false,
        },
        hasEditor: false,
        contentPadding: EdgeInsets.zero,
        requiredCapabilities: const {
          PlatformCapability.filesystem,
          PlatformCapability.processes,
        },
      );

  static const String kTypeId = 'board.yolo_assistant';

  @override
  Color get accentColor => const Color(0xFF8B5CF6);

  @override
  Widget? buildIconWidget(BuildContext context, {double size = 16}) {
    return SvgPicture.asset(
      'assets/icon/yolo_assistant.svg',
      width: size,
      height: size,
    );
  }
}
