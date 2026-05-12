import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Run Configs panels (`board.run_configs`).
class RunConfigsCliHandler extends PanelCliHandler {
  const RunConfigsCliHandler();

  @override
  String get typeId => 'board.run_configs';

  @override
  List<String> get supportedActions => [
    'list',
    'add',
    'remove',
    'run',
    'stop',
    'output',
    'config',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'configurations':
          panel.state['configurations'] as List<dynamic>? ?? <dynamic>[],
      'activeConfigId': panel.state['activeConfigId'] ?? '',
      'isRunning': panel.state['isRunning'] ?? false,
    };
  }

  List<Map<String, dynamic>> _configs(BoardPanelInstance panel) =>
      (panel.state['configurations'] as List<dynamic>?)
          ?.whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList() ??
      [];

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'list':
        return CliActionResult(data: getContent(panel));

      case 'add':
        final name = args['name'] as String?;
        final command = args['command'] as String?;
        if (name == null || command == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "name" and/or "command"',
          );
        }
        final configs = _configs(panel);
        final id = DateTime.now().millisecondsSinceEpoch.toString();
        configs.add(<String, dynamic>{
          'id': id,
          'name': name,
          'command': command,
          'workingDir': args['workingDir'] as String? ?? '',
          'envVars': <String, String>{},
          'status': 'idle',
          'output': '',
        });
        return CliActionResult(
          message: 'Configuration "$name" added (id: $id)',
          stateUpdate: {'configurations': configs, 'activeConfigId': id},
        );

      case 'remove':
        final id = args['id'] as String?;
        if (id == null) {
          return const CliActionResult(ok: false, message: 'Missing "id"');
        }
        final configs = _configs(panel);
        final before = configs.length;
        configs.removeWhere((c) => c['id'] == id);
        if (configs.length == before) {
          return CliActionResult(
            ok: false,
            message: 'Configuration "$id" not found',
          );
        }
        final active = panel.state['activeConfigId'] as String? ?? '';
        return CliActionResult(
          message: 'Configuration removed',
          stateUpdate: {
            'configurations': configs,
            if (active == id) 'activeConfigId': '',
          },
        );

      case 'run':
        final id =
            args['id'] as String? ??
            panel.state['activeConfigId'] as String? ??
            '';
        if (id.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'No configuration selected',
          );
        }
        final configs = _configs(panel);
        final idx = configs.indexWhere((c) => c['id'] == id);
        if (idx < 0) {
          return CliActionResult(
            ok: false,
            message: 'Configuration "$id" not found',
          );
        }
        configs[idx]['status'] = 'running';
        configs[idx]['output'] =
            '> ${configs[idx]['command']}\nStarting in ${configs[idx]['workingDir'] ?? '.'}\n';
        return CliActionResult(
          message: 'Running "${configs[idx]['name']}"',
          stateUpdate: {
            'configurations': configs,
            'activeConfigId': id,
            'isRunning': true,
            'output': configs[idx]['output'] as String,
          },
        );

      case 'stop':
        final id =
            args['id'] as String? ??
            panel.state['activeConfigId'] as String? ??
            '';
        if (id.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'No configuration selected',
          );
        }
        final configs = _configs(panel);
        final idx = configs.indexWhere((c) => c['id'] == id);
        if (idx < 0) {
          return CliActionResult(
            ok: false,
            message: 'Configuration "$id" not found',
          );
        }
        configs[idx]['status'] = 'idle';
        final out = '${configs[idx]['output'] as String? ?? ''}\n[stopped]\n';
        configs[idx]['output'] = out;
        return CliActionResult(
          message: 'Stopped "${configs[idx]['name']}"',
          stateUpdate: {
            'configurations': configs,
            'isRunning': false,
            'output': out,
          },
        );

      case 'output':
        final id =
            args['id'] as String? ??
            panel.state['activeConfigId'] as String? ??
            '';
        if (id.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'No configuration selected',
          );
        }
        final configs = _configs(panel);
        final config =
            configs
                .where((c) => c['id'] == id)
                .cast<Map<String, dynamic>?>()
                .firstOrNull;
        if (config == null) {
          return CliActionResult(
            ok: false,
            message: 'Configuration "$id" not found',
          );
        }
        return CliActionResult(
          data: {
            'id': id,
            'name': config['name'],
            'output': config['output'] ?? '',
          },
        );

      case 'config':
        final id =
            args['id'] as String? ??
            panel.state['activeConfigId'] as String? ??
            '';
        if (id.isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'No configuration selected',
          );
        }
        final configs = _configs(panel);
        final config =
            configs
                .where((c) => c['id'] == id)
                .cast<Map<String, dynamic>?>()
                .firstOrNull;
        if (config == null) {
          return CliActionResult(
            ok: false,
            message: 'Configuration "$id" not found',
          );
        }
        return CliActionResult(data: config);

      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'list': const CliActionHelp(description: 'List all run configurations'),
    'add': const CliActionHelp(
      description: 'Add a new run configuration',
      params: {
        'name': 'Configuration name (required)',
        'command': 'Shell command to execute (required)',
        'workingDir': 'Working directory (optional)',
      },
      example: '{"name": "Flutter Run", "command": "flutter run -d macos"}',
    ),
    'remove': const CliActionHelp(
      description: 'Remove a configuration by id',
      params: {'id': 'Configuration ID'},
    ),
    'run': const CliActionHelp(
      description: 'Start a configuration',
      params: {'id': 'Configuration ID (defaults to active)'},
    ),
    'stop': const CliActionHelp(
      description: 'Stop a running configuration',
      params: {'id': 'Configuration ID (defaults to active)'},
    ),
    'output': const CliActionHelp(
      description: 'Get output of a configuration',
      params: {'id': 'Configuration ID (defaults to active)'},
    ),
    'config': const CliActionHelp(
      description: 'Get full details of a configuration',
      params: {'id': 'Configuration ID (defaults to active)'},
    ),
  };
}
