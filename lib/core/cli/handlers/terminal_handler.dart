import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Terminal panels (`board.terminal`).
class TerminalCliHandler extends PanelCliHandler {
  const TerminalCliHandler();

  @override
  String get typeId => 'board.terminal';

  @override
  List<String> get supportedActions => ['config', 'set-dir'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'config': panel.state['config'] as Map<String, dynamic>? ?? <String, dynamic>{}};
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'config':
        return CliActionResult(data: getContent(panel));
      case 'set-dir':
        final dir = args['dir'] as String? ?? args['path'] as String?;
        if (dir == null) {
          return const CliActionResult(ok: false, message: 'Missing "dir"');
        }
        final config = Map<String, dynamic>.from(
          (panel.state['config'] as Map<String, dynamic>?) ?? <String, dynamic>{},
        );
        config['workingDir'] = dir;
        return CliActionResult(
          message: 'Working directory set to $dir',
          stateUpdate: {'config': config},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
