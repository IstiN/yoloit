import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/ui/chat_header_menu.dart';

final _chatPanelDefaultColors = AppColorScheme.fromAccent(Colors.green);

/// Board panel plugin for an AI chat powered by CLI tools (Copilot, etc.).
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
  List<Widget> buildHeaderActions(
    BuildContext context,
    BoardPanelInstance panel,
    ValueChanged<Map<String, dynamic>> onUpdateState, {
    void Function(double w, double h)? onResize,
    VoidCallback? onEditColor,
  }) {
    return [
      ChatHeaderMenu(
        panel: panel,
        onEditColor: onEditColor ?? () {},
        onUpdateState: onUpdateState,
      ),
    ];
  }

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return ChatPanelWidget(
      panel: panel,
      onUpdateState: renderContext.onUpdateState,
      onCreateLinkedPanel: renderContext.onCreateLinkedPanel,
      remoteInfo: renderContext.remoteInfo,
    );
  }
}
