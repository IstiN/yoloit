import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_widget.dart';

final _boardTerminalDefaultColors = AppColorScheme.fromAccent(Colors.green);

class BoardTerminalPanelPlugin extends BoardPanelPlugin {
  const BoardTerminalPanelPlugin();

  static const kTypeId = 'board.terminal';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Terminal';

  @override
  IconData get icon => Icons.terminal;

  @override
  Color get accentColor => _boardTerminalDefaultColors.accentGreen;

  @override
  Size get defaultSize => const Size(520, 360);

  @override
  Map<String, dynamic> get initialState => {
    'config':
        const BoardTerminalConfig(
          sessionId: '',
          sessionName: '',
          workingDir: '',
        ).toJson(),
  };

  @override
  bool get showInCatalog => false;

  @override
  bool get supportsHeadlessRender => false; // native PTY — requires live terminal session

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return BoardTerminalPanelWidget(
      panel: panel,
      onUpdateState: renderContext.onUpdateState,
      remoteInfo: renderContext.remoteInfo,
    );
  }
}
