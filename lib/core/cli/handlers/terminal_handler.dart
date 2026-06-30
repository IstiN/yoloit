import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';

/// CLI handler for Terminal panels (`board.terminal`).
class TerminalCliHandler extends PanelCliHandler {
  const TerminalCliHandler();

  @override
  String get typeId => 'board.terminal';

  @override
  List<String> get supportedActions => ['config', 'set-dir', 'set-session', 'output'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'config':
          panel.state['config'] as Map<String, dynamic>? ?? <String, dynamic>{},
    };
  }

  CliActionResult _readOutput(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final rawConfig = panel.state['config'];
    if (rawConfig is! Map<String, dynamic>) {
      return const CliActionResult(
        ok: false,
        message: 'Terminal panel is not configured',
      );
    }
    final config = BoardTerminalConfig.fromJson(rawConfig);
    if (config.sessionId.trim().isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Terminal panel has no active session',
      );
    }

    final session = BoardTerminalSessionManager.instance.sessionFor(
      config.sessionId,
    );
    if (session == null) {
      return CliActionResult(
        ok: false,
        message: 'Terminal session ${config.sessionId} is not live',
      );
    }

    final raw = args['raw'] as bool? ?? false;
    if (raw) {
      return CliActionResult(
        data: {
          'sessionId': config.sessionId,
          'raw': session.rawHistory(),
        },
      );
    }

    final limitArg = args['limit'] as int?;
    const maxLimit = 300;
    final limit = limitArg == null || limitArg <= 0 ? 80 : limitArg.clamp(1, maxLimit);
    final lines = session.lastLines(limit);
    return CliActionResult(
      data: {
        'sessionId': config.sessionId,
        'lines': lines,
        'total': lines.length,
        'limit': limit,
      },
    );
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
          (panel.state['config'] as Map<String, dynamic>?) ??
              <String, dynamic>{},
        );
        config['workingDir'] = dir;
        return CliActionResult(
          message: 'Working directory set to $dir',
          stateUpdate: {'config': config},
        );
      case 'set-session':
        final sessionId =
            args['sessionId'] as String? ?? args['session'] as String?;
        if (sessionId == null || sessionId.trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "sessionId" field',
          );
        }
        final config = Map<String, dynamic>.from(
          (panel.state['config'] as Map<String, dynamic>?) ??
              <String, dynamic>{},
        );
        config['sessionId'] = sessionId.trim();
        return CliActionResult(
          message: 'Terminal session set to $sessionId',
          stateUpdate: {'config': config},
        );
      case 'output':
        return _readOutput(args, panel);
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'config': const CliActionHelp(
      description: 'Read terminal panel configuration',
    ),
    'set-dir': const CliActionHelp(
      description: 'Set terminal working directory for the panel',
      params: {'dir': 'Absolute working directory path'},
      example: 'yoloit do "<board>" "<terminal>" set-dir \'{"dir":"/repo"}\'',
    ),
    'set-session': const CliActionHelp(
      description: 'Attach the terminal panel to an existing session id',
      params: {'sessionId': 'Terminal session id (required)'},
      example:
          'yoloit do "<board>" "<terminal>" set-session \'{"sessionId":"sess_123"}\'',
    ),
    'output': const CliActionHelp(
      description: 'Read recent output from the live terminal session',
      params: {
        'limit': 'Maximum number of plain-text lines to return (default 80, max 300)',
        'raw': 'Return raw ANSI bytes instead of plain-text lines (default false)',
      },
      example:
          'yoloit do "<board>" "<terminal>" output \'{"limit":40}\'',
    ),
  };
}
