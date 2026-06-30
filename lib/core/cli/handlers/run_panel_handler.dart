import 'package:yoloit/core/cli/handlers/run_configs_handler.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for detached Run panels (`board.run`).
///
/// Extends [RunConfigsCliHandler] with panel-state actions used by the Run
/// panel widget (`set-group`, `select-session`, `clear-session`, `get`).
class RunPanelCliHandler extends RunConfigsCliHandler {
  const RunPanelCliHandler() : super(panelTypeId: 'board.run');

  @override
  List<String> get supportedActions => [
    'get',
    'set-group',
    'select-session',
    'clear-session',
    ...super.supportedActions,
  ];

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(
          data: {
            'group': _panelGroup(panel),
            'activeSessionId': panel.state['activeSessionId'],
            'hiddenSessionIds': _hiddenSessionIds(panel),
          },
        );
      case 'set-group':
        final group = args['group']?.toString().trim();
        if (group == null || group.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "group" field',
          );
        }
        return CliActionResult(
          message: 'Run panel group set to $group',
          stateUpdate: {'group': group},
        );
      case 'select-session':
        final sessionId = args['sessionId']?.toString().trim();
        if (sessionId == null || sessionId.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "sessionId" field',
          );
        }
        return CliActionResult(
          message: 'Active session set to $sessionId',
          stateUpdate: {'activeSessionId': sessionId},
        );
      case 'clear-session':
        return const CliActionResult(
          message: 'Active session cleared',
          stateUpdate: {'activeSessionId': null},
        );
      default:
        return super.handleAction(action, args, panel);
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    ...super.actionHelp,
    'get': const CliActionHelp(
      description: 'Read run panel state (group, active session, hidden tabs)',
    ),
    'set-group': const CliActionHelp(
      description: 'Set the run session group scope for this panel',
      params: {'group': 'Group id (required)'},
      example:
          'yoloit do "<board>" "<run>" set-group \'{"group":"review"}\'',
    ),
    'select-session': const CliActionHelp(
      description: 'Focus a run session tab in this panel',
      params: {'sessionId': 'Run session id (required)'},
    ),
    'clear-session': const CliActionHelp(
      description: 'Clear the focused run session tab',
    ),
  };

  String _panelGroup(BoardPanelInstance panel) {
    final group = panel.state['group'];
    if (group is String && group.trim().isNotEmpty) {
      return group.trim();
    }
    return panel.id;
  }

  List<String> _hiddenSessionIds(BoardPanelInstance panel) {
    final raw = panel.state['hiddenSessionIds'];
    if (raw is List) {
      return raw.whereType<String>().map((id) => id.trim()).toList();
    }
    return const [];
  }
}
