import 'package:flutter/material.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

/// Board panel plugin for the YoLo Assistant — an AI chat with voice mode.
class YoloAssistantPlugin extends BoardPanelPlugin {
  const YoloAssistantPlugin();

  static const String kTypeId = 'board.yolo_assistant';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'YoLo Assistant';

  @override
  IconData get icon => Icons.smart_toy;

  @override
  Color get accentColor => const Color(0xFF8B5CF6);

  @override
  Size get defaultSize => const Size(420, 560);

  @override
  Map<String, dynamic> get initialState => {
    'messages': <Map<String, dynamic>>[],
    'activeSkills': <String>['Terminal', 'Board Control', 'Web Search'],
    'mode': 'text',
    'isListening': false,
    'isSpeaking': false,
  };

  @override
  bool get hasEditor => false;

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return YoloAssistantWidget(
      panel: panel,
      onUpdateState: renderContext.onUpdateState,
    );
  }
}
