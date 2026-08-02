import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/runs/data/run_bridge.dart';
import 'package:yoloit/features/runs/models/run_config.dart';

/// CLI handler for Run Configs panels (`board.run_configs`).
class RunConfigsCliHandler extends PanelCliHandler {
  const RunConfigsCliHandler({this.panelTypeId = 'board.run_configs'});

  final String panelTypeId;

  @override
  String get typeId => panelTypeId;

  @override
  List<String> get supportedActions => [
    'list',
    'add',
    'update',
    'remove',
    'run',
    'stop',
    'detach',
    'attach',
    'input',
    'output',
    'config',
    'close',
    'logs',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final group = _resolveGroup(panel: panel);
    return _getContentForGroup(group);
  }

  Map<String, dynamic> _getContentForGroup(String group) {
    final bridge = RunBridge.instance;
    final scopedConfigs =
        bridge.state.configs.where((config) => config.group == group).toList();
    final scopedSessions =
        bridge.state.sessions
            .where((session) => session.config.group == group)
            .toList();
    return {
      'group': group,
      'workspacePath': bridge.workspacePath,
      'configurations': scopedConfigs.map(bridge.serializeConfig).toList(),
      'sessions': scopedSessions.map(bridge.serializeSession).toList(),
      'activeSessionId': bridge.state.activeSessionId,
      'isRunning': scopedSessions.any(
        (session) => session.status.name == 'running',
      ),
    };
  }

  List<RunQuickAction>? _parseQuickActions(dynamic value) =>
      (value as List?)
          ?.whereType<Map<String, dynamic>>()
          .map(RunQuickAction.fromJson)
          .where((action) => action.command.trim().isNotEmpty)
          .toList();

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final actionGroup = _resolveGroup(panel: panel, args: args);
    final handlers = <String, Future<CliActionResult> Function()>{
      'list': () => _handleList(actionGroup),
      'add': () => _handleAdd(args, actionGroup),
      'remove': () => _handleRemove(args, actionGroup),
      'update': () => _handleUpdate(args, actionGroup),
      'run': () => _handleRun(args, actionGroup),
      'stop': () => _handleStop(args, actionGroup),
      'input': () => _handleInput(args, actionGroup),
      'detach': () => _handleDetach(args, actionGroup),
      'attach': () => _handleAttach(args, actionGroup),
      'output': () => _handleOutput(args, actionGroup),
      'close': () => _handleClose(args, actionGroup),
      'logs': () => _handleLogs(args, actionGroup),
      'config': () => _handleConfig(args, actionGroup),
    };
    final handler = handlers[action];
    if (handler == null) {
      return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
    return handler();
  }

  Future<CliActionResult> _handleList(String actionGroup) async {
    return CliActionResult(data: _getContentForGroup(actionGroup));
  }

  Future<CliActionResult> _handleAdd(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
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
          existing.group == actionGroup &&
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
      group: actionGroup,
      workingDir: args['workingDir'] as String?,
      env:
          args['env'] is Map
              ? Map<String, String>.from(args['env'] as Map)
              : const {},
      isFlutterRun: args['isFlutterRun'] as bool? ?? false,
      quickActions: _parseQuickActions(args['quickActions']) ?? const [],
    );
    return CliActionResult(
      message: 'Configuration "$name" added (id: ${config.id})',
      data: RunBridge.instance.serializeConfig(config),
    );
  }

  Future<CliActionResult> _handleRemove(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    final identifier = args['id'] as String? ?? args['name'] as String?;
    final config = RunBridge.instance.findConfig(identifier, actionGroup);
    if (config == null) {
      return const CliActionResult(ok: false, message: 'Missing "id"');
    }
    await RunBridge.instance.removeConfig(config.id);
    return const CliActionResult(message: 'Configuration removed');
  }

  Future<CliActionResult> _handleUpdate(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    final identifier = args['id'] as String? ?? args['name'] as String?;
    if (identifier == null || identifier.trim().isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "id"');
    }
    try {
      final updated = await RunBridge.instance.updateConfig(
        identifier: identifier,
        group: actionGroup,
        name: args['newName'] as String? ?? args['nameOverride'] as String?,
        command: args['command'] as String?,
        workingDir: args['workingDir'] as String?,
        env:
            args['env'] is Map
                ? Map<String, String>.from(args['env'] as Map)
                : null,
        isFlutterRun: args['isFlutterRun'] as bool?,
        quickActions: _parseQuickActions(args['quickActions']),
      );
      return CliActionResult(
        message: 'Configuration updated',
        data: RunBridge.instance.serializeConfig(updated),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleRun(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    try {
      final session = await RunBridge.instance.startConfig(
        args['id'] as String? ?? args['name'] as String?,
        actionGroup,
      );
      return CliActionResult(
        message: 'Running "${session.config.name}"',
        data: RunBridge.instance.serializeSession(session),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleStop(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    try {
      final session = await RunBridge.instance.stopSession(
        args['sessionId'] as String? ??
            args['id'] as String? ??
            args['name'] as String?,
        actionGroup,
      );
      return CliActionResult(
        message: 'Stopped "${session.config.name}"',
        data: RunBridge.instance.serializeSession(session),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleInput(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
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
        group: actionGroup,
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
  }

  Future<CliActionResult> _handleDetach(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    try {
      final session = await RunBridge.instance.detachSession(
        args['sessionId'] as String? ??
            args['id'] as String? ??
            args['name'] as String?,
        actionGroup,
      );
      return CliActionResult(
        message: 'Detached "${session.config.name}"',
        data: RunBridge.instance.serializeSession(session),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleAttach(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    try {
      final session = await RunBridge.instance.attachSession(
        identifier:
            args['sessionId'] as String? ??
            args['id'] as String? ??
            args['name'] as String?,
        group: actionGroup,
        runningOnly: args['runningOnly'] as bool? ?? true,
      );
      return CliActionResult(
        message: 'Attached "${session.config.name}"',
        data: RunBridge.instance.serializeSession(session),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleOutput(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    final session = RunBridge.instance.findSession(
      args['sessionId'] as String? ??
          args['id'] as String? ??
          args['name'] as String?,
      group: actionGroup,
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
  }

  Future<CliActionResult> _handleClose(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    try {
      final session = await RunBridge.instance.removeSession(
        args['sessionId'] as String? ??
            args['id'] as String? ??
            args['name'] as String?,
        actionGroup,
      );
      return CliActionResult(
        message: 'Closed "${session.config.name}"',
        data: RunBridge.instance.serializeSession(session),
      );
    } on StateError catch (error) {
      return CliActionResult(ok: false, message: error.message);
    }
  }

  Future<CliActionResult> _handleLogs(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    final session = RunBridge.instance.findSession(
      args['sessionId'] as String? ??
          args['id'] as String? ??
          args['name'] as String?,
      group: actionGroup,
    );
    if (session == null) {
      return const CliActionResult(
        ok: false,
        message: 'Run session not found',
      );
    }
    final limit = args['limit'] as int?;
    final outputLines = session.output;
    final effectiveLines =
        limit != null && limit > 0 && limit < outputLines.length
            ? outputLines.sublist(outputLines.length - limit)
            : outputLines;
    return CliActionResult(
      data: {
        ...RunBridge.instance.serializeSession(session),
        'outputLines':
            effectiveLines
                .map(
                  (line) => {
                    'text': line.text,
                    'isError': line.isError,
                    'timestamp': line.timestamp.toIso8601String(),
                  },
                )
                .toList(),
        'output': effectiveLines.map((line) => line.text).join('\n'),
        'limit': limit,
      },
    );
  }

  Future<CliActionResult> _handleConfig(
    Map<String, dynamic> args,
    String actionGroup,
  ) async {
    final config = RunBridge.instance.findConfig(
      args['id'] as String? ?? args['name'] as String?,
      actionGroup,
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
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'list': const CliActionHelp(
      description: 'List run configurations in current group',
      params: {'group': 'Group scope override (optional)'},
    ),
    'add': const CliActionHelp(
      description: 'Add a new run configuration',
      params: {
        'name': 'Configuration name (required)',
        'command': 'Shell command to execute (required)',
        'group': 'Group scope override (optional)',
        'workingDir':
            'Absolute path to working directory (optional). Must be a full path, e.g. /Users/me/project — do not use relative paths like "."',
        'env': 'Environment variables map (optional)',
        'isFlutterRun': 'Whether Flutter hot reload/restart controls apply',
        'quickActions':
            'List of quick actions: [{label, icon, command, appendNewline?}]',
      },
      example:
          '{"name":"Flutter Run","command":"flutter run -d macos","workingDir":"/Users/me/project","quickActions":[{"label":"Hot Reload","icon":"local_fire_department","command":"r"},{"label":"Hot Restart","icon":"restart_alt","command":"R"}]}',
    ),
    'remove': const CliActionHelp(
      description: 'Remove a configuration by id or name',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
        'group': 'Group scope override (optional)',
      },
    ),
    'update': const CliActionHelp(
      description: 'Update a configuration by id or name',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
        'group': 'Group scope override (optional)',
        'newName': 'New display name',
        'command': 'New command',
        'workingDir':
            'Absolute path to working directory. Must be a full path, e.g. /Users/me/project — do not use relative paths like "."',
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
        'group': 'Group scope override (optional)',
      },
    ),
    'stop': const CliActionHelp(
      description: 'Stop the latest running session for a config',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
        'group': 'Group scope override (optional)',
      },
    ),
    'detach': const CliActionHelp(
      description: 'Detach from active run session (session keeps running)',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
        'group': 'Group scope override (optional)',
      },
    ),
    'attach': const CliActionHelp(
      description: 'Attach run console to a session in this group',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
        'group': 'Group scope override (optional)',
        'runningOnly': 'Prefer running sessions (default: true)',
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
        'group': 'Group scope override (optional)',
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
        'group': 'Group scope override (optional)',
      },
    ),
    'close': const CliActionHelp(
      description: 'Close a run session tab and remove it from the panel',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
        'group': 'Group scope override (optional)',
      },
      example:
          'yoloit do "<board>" "<run-configs>" close \'{"sessionId":"sess_123"}\'',
    ),
    'logs': const CliActionHelp(
      description: 'Read full output/logs of a run session by id or name',
      params: {
        'sessionId': 'Run session ID',
        'id': 'Configuration ID',
        'name': 'Configuration name',
        'group': 'Group scope override (optional)',
        'limit': 'Maximum number of output lines to return (optional)',
      },
      example:
          'yoloit do "<board>" "<run-configs>" logs \'{"name":"Flutter Run","limit":100}\'',
    ),
    'config': const CliActionHelp(
      description: 'Get full details of a configuration',
      params: {
        'id': 'Configuration ID',
        'name': 'Configuration name (alternative to id)',
        'group': 'Group scope override (optional)',
      },
    ),
  };

  String _resolveGroup({
    required BoardPanelInstance panel,
    Map<String, dynamic>? args,
  }) {
    final argGroup = args?['group'];
    if (argGroup is String && argGroup.trim().isNotEmpty) {
      return argGroup.trim();
    }
    final panelGroup = panel.state['group'];
    if (panelGroup is String && panelGroup.trim().isNotEmpty) {
      return panelGroup.trim();
    }
    return panel.id;
  }
}
