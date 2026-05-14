import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/runs/data/run_bridge.dart';
import 'package:yoloit/features/runs/models/run_config.dart';

/// CLI handler for Run Configs panels (`board.run_configs`).
class RunConfigsCliHandler extends PanelCliHandler {
  const RunConfigsCliHandler();

  @override
  String get typeId => 'board.run_configs';

  @override
  List<String> get supportedActions => [
    'list',
    'add',
    'update',
    'remove',
    'run',
    'stop',
    'input',
    'output',
    'config',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final bridge = RunBridge.instance;
    return {
      'workspacePath': bridge.workspacePath,
      'configurations':
          bridge.state.configs.map(bridge.serializeConfig).toList(),
      'sessions': bridge.state.sessions.map(bridge.serializeSession).toList(),
      'activeSessionId': bridge.state.activeSessionId,
      'isRunning': bridge.state.sessions.any(
        (session) => session.status.name == 'running',
      ),
    };
  }

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
        final normalizedName = name.trim().toLowerCase();
        final normalizedCommand = command.trim().toLowerCase();
        final normalizedWorkingDir =
            (args['workingDir'] as String? ?? '').trim();
        final duplicate = RunBridge.instance.state.configs.firstWhere(
          (existing) =>
              existing.name.trim().toLowerCase() == normalizedName &&
              existing.command.trim().toLowerCase() == normalizedCommand &&
              (existing.workingDir ?? '').trim() == normalizedWorkingDir,
          orElse: () => const RunConfig(id: '', name: '', command: ''),
        );
        if (duplicate.id.isNotEmpty) {
          return CliActionResult(
            message: 'Configuration already exists (id: ${duplicate.id})',
            data: RunBridge.instance.serializeConfig(duplicate),
          );
        }
        final config = await RunBridge.instance.addConfig(
          name: name,
          command: command,
          workingDir: args['workingDir'] as String?,
          env:
              args['env'] is Map
                  ? Map<String, String>.from(args['env'] as Map)
                  : const {},
          isFlutterRun: args['isFlutterRun'] as bool? ?? false,
          quickActions:
              (args['quickActions'] as List?)
                  ?.whereType<Map<String, dynamic>>()
                  .map(RunQuickAction.fromJson)
                  .where((action) => action.command.trim().isNotEmpty)
                  .toList() ??
              const [],
        );
        return CliActionResult(
          message: 'Configuration "$name" added (id: ${config.id})',
          data: RunBridge.instance.serializeConfig(config),
        );

      case 'remove':
        final identifier = args['id'] as String? ?? args['name'] as String?;
        final config = RunBridge.instance.findConfig(identifier);
        if (config == null) {
          return const CliActionResult(ok: false, message: 'Missing "id"');
        }
        await RunBridge.instance.removeConfig(config.id);
        return const CliActionResult(message: 'Configuration removed');

      case 'update':
        final identifier = args['id'] as String? ?? args['name'] as String?;
        if (identifier == null || identifier.trim().isEmpty) {
          return const CliActionResult(ok: false, message: 'Missing "id"');
        }
        try {
          final updated = await RunBridge.instance.updateConfig(
            identifier: identifier,
            name: args['newName'] as String? ?? args['nameOverride'] as String?,
            command: args['command'] as String?,
            workingDir: args['workingDir'] as String?,
            env:
                args['env'] is Map
                    ? Map<String, String>.from(args['env'] as Map)
                    : null,
            isFlutterRun: args['isFlutterRun'] as bool?,
            quickActions:
                (args['quickActions'] as List?)
                    ?.whereType<Map<String, dynamic>>()
                    .map(RunQuickAction.fromJson)
                    .where((action) => action.command.trim().isNotEmpty)
                    .toList(),
          );
          return CliActionResult(
            message: 'Configuration updated',
            data: RunBridge.instance.serializeConfig(updated),
          );
        } on StateError catch (error) {
          return CliActionResult(ok: false, message: error.message);
        }

      case 'run':
        try {
          final session = await RunBridge.instance.startConfig(
            args['id'] as String? ?? args['name'] as String?,
          );
          return CliActionResult(
            message: 'Running "${session.config.name}"',
            data: RunBridge.instance.serializeSession(session),
          );
        } on StateError catch (error) {
          return CliActionResult(ok: false, message: error.message);
        }

      case 'stop':
        try {
          final session = await RunBridge.instance.stopSession(
            args['sessionId'] as String? ??
                args['id'] as String? ??
                args['name'] as String?,
          );
          return CliActionResult(
            message: 'Stopped "${session.config.name}"',
            data: RunBridge.instance.serializeSession(session),
          );
        } on StateError catch (error) {
          return CliActionResult(ok: false, message: error.message);
        }

      case 'input':
        final rawText = args['text'] as String? ?? args['input'] as String?;
        if (rawText == null || rawText.isEmpty) {
          return const CliActionResult(ok: false, message: 'Missing "text"');
        }
        try {
          final session = await RunBridge.instance.sendInput(
            identifier:
                args['sessionId'] as String? ??
                args['id'] as String? ??
                args['name'] as String?,
            text: rawText,
            appendNewline: args['appendNewline'] as bool? ?? false,
          );
          return CliActionResult(
            message: 'Input sent to "${session.config.name}"',
            data: RunBridge.instance.serializeSession(session),
          );
        } on StateError catch (error) {
          return CliActionResult(ok: false, message: error.message);
        }

      case 'output':
        final session = RunBridge.instance.findSession(
          args['sessionId'] as String? ??
              args['id'] as String? ??
              args['name'] as String?,
        );
        if (session == null) {
          return const CliActionResult(
            ok: false,
            message: 'Run session not found',
          );
        }
        return CliActionResult(
          data: RunBridge.instance.serializeSession(session),
        );

      case 'config':
        final config = RunBridge.instance.findConfig(
          args['id'] as String? ?? args['name'] as String?,
        );
        if (config == null) {
          return const CliActionResult(
            ok: false,
            message: 'Configuration not found',
          );
        }
        return CliActionResult(
          data: RunBridge.instance.serializeConfig(config),
        );

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
        'env': 'Environment variables map (optional)',
        'isFlutterRun': 'Whether Flutter hot reload/restart controls apply',
        'quickActions':
            'List of quick actions: [{label, icon, command, appendNewline?}]',
      },
      example:
          '{"name":"Flutter Run","command":"flutter run -d macos","quickActions":[{"label":"Hot Reload","icon":"local_fire_department","command":"r"},{"label":"Hot Restart","icon":"restart_alt","command":"R"}]}',
    ),
    'remove': const CliActionHelp(
      description: 'Remove a configuration by id or name',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
      },
    ),
    'update': const CliActionHelp(
      description: 'Update a configuration by id or name',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
        'newName': 'New display name',
        'command': 'New command',
        'workingDir': 'Working directory override',
        'env': 'Environment variables map',
        'isFlutterRun': 'Whether Flutter controls are shown',
        'quickActions':
            'Replace quick actions list: [{label, icon, command, appendNewline?}]',
      },
      example:
          '{"id":"preset_flutter_run_macos","quickActions":[{"label":"Hot Reload","icon":"local_fire_department","command":"r"}]}',
    ),
    'run': const CliActionHelp(
      description: 'Start a configuration',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
      },
    ),
    'stop': const CliActionHelp(
      description: 'Stop the latest running session for a config',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
      },
    ),
    'input': const CliActionHelp(
      description: 'Send stdin text to a running session',
      params: {
        'text': 'Input text to send (required)',
        'appendNewline': 'Append trailing newline (default: false)',
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
      },
      example:
          '{"id":"preset_flutter_run_macos","text":"r","appendNewline":false}',
    ),
    'output': const CliActionHelp(
      description: 'Get output of the latest matching run session',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
      },
    ),
    'config': const CliActionHelp(
      description: 'Get full details of a configuration',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
      },
    ),
  };
}
