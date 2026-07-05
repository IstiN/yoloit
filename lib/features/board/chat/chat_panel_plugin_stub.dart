import 'package:flutter/material.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/unsupported_capability_panel.dart';

final _chatPanelDefaultColors = AppColorScheme.fromAccent(Colors.green);

/// Web stub for the AI chat panel.
///
/// The current chat implementation is tightly coupled to local CLI providers.
/// A future web version could use cloud providers; for now it renders a
/// placeholder.
class ChatPanelPlugin extends BoardPanelPlugin {
  const ChatPanelPlugin();

  static const String kTypeId = 'board.chat';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'AI Chat';

  @override
  IconData get icon => Icons.auto_awesome;

  @override
  Color get accentColor => _chatPanelDefaultColors.accentGreen;

  @override
  Size get defaultSize => const Size(420, 500);

  @override
  Map<String, dynamic> get initialState => {
        'config': const ChatSessionConfig(sessionName: '', workingDir: '').toJson(),
        'configured': false,
      };

  @override
  bool get showInCatalog => false;

  @override
  bool get hasEditor => false;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Set<PlatformCapability> get requiredCapabilities => const {
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
