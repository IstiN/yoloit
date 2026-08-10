import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/cli/cli_text_argument_resolver.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/ui_cli_inprocess.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_locator.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_base.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_shared.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';

class YoloitCliToolExecutor implements YoloitToolExecutor {
  YoloitCliToolExecutor({
    this.execute = true,
    this.executablePath,
    this.timeout = const Duration(seconds: 30),
  });

  final bool execute;
  final String? executablePath;
  final Duration timeout;

  /// Test hook overriding the CLI server port used for the in-process `ui:`
  /// invocation path, so tests can point it at a fake CLI HTTP server.
  @visibleForTesting
  static int? debugCliPortOverride;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    final resolved = resolveToolCall(functionName);
    if (resolved.response != null) return resolved.response!;
    final tool = resolved.tool!;

    final normalized =
        argumentsPreNormalized
            ? arguments
            : YoloitCliToolArgumentNormalizer.normalize(
              functionName: functionName,
              arguments: arguments,
              userMessage: '',
              runtimeContext: runtimeContext,
            );
    final List<String> cliArgs;
    try {
      cliArgs = _buildCliArgs(tool, normalized, runtimeContext);
    } on ArgumentError catch (e) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': false,
        'error': '$e',
      });
    }
    final validation = _validateCliArgs(tool, cliArgs);
    final rendered = _renderCommand(cliArgs);
    final guard = _preExecutionResult(tool, arguments, validation, rendered);
    if (guard != null) return guard;

    final cliPort = debugCliPortOverride ?? CliServer.instance.port;
    if (cliPort != null && tool.command.startsWith('ui:')) {
      final inProcess = await _tryInvokeInProcess(tool, normalized, cliPort);
      if (inProcess != null) return inProcess;
    }

    final executable = executablePath ?? _resolveYoloitExecutable();
    File? boardApplyYamlTemp;
    var runArgs = cliArgs;
    if (tool.command == 'board:apply') {
      final prepared = await _prepareBoardApply(
        tool,
        normalized,
        cliArgs,
        runtimeContext,
      );
      if (prepared.error != null) return prepared.error!;
      boardApplyYamlTemp = prepared.tempFile;
      if (prepared.runArgs != null) runArgs = prepared.runArgs!;
    }
    try {
      return await _runCliProcess(
        executable: executable,
        runArgs: runArgs,
        cliPort: cliPort,
        tool: tool,
        rendered: rendered,
      );
    } finally {
      _deleteTempFile(boardApplyYamlTemp);
    }
  }

  /// Returns a JSON response when the invocation must stop before executing
  /// the CLI (validation failure, unconfirmed destructive command, or a
  /// dry run with `execute == false`), or null when execution may proceed.
  String? _preExecutionResult(
    YoloitCliTool tool,
    Map<String, Object?> arguments,
    String? validation,
    String rendered,
  ) {
    if (validation != null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': false,
        'command': rendered,
        'error': validation,
      });
    }
    if (tool.destructive && !_confirmedDestructive(arguments)) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'executed': false,
        'command': rendered,
        'error':
            'Destructive tool "${tool.command}" requires confirm=true after explicit user confirmation.',
      });
    }
    if (!execute) {
      return jsonEncode(<String, Object?>{
        'ok': true,
        'executed': false,
        'command': rendered,
      });
    }
    return null;
  }

  /// Attempts to execute a `ui:` command in-process via the running CLI
  /// server. Returns the JSON response, or null when the in-process client
  /// could not handle the command.
  Future<String?> _tryInvokeInProcess(
    YoloitCliTool tool,
    Map<String, Object?> normalized,
    int cliPort,
  ) async {
    final inProcess = await UiCliInProcessClient.tryExecute(
      command: tool.command,
      arguments: normalized,
      port: cliPort,
    );
    if (inProcess == null) return null;
    var ok = true;
    try {
      final decoded = jsonDecode(inProcess);
      if (decoded is Map && decoded['ok'] is bool) {
        ok = decoded['ok'] as bool;
      }
    } catch (_) {}
    if (ok && !_isReadOnlyCommand(tool.command)) {
      BoardEventBus.instance.emit(BoardToolMutationEvent(tool.command));
    }
    return inProcess;
  }

  /// Writes the board:apply YAML payload to a temp file and builds the
  /// positional CLI arguments for it. Returns an error JSON when the board
  /// cannot be resolved.
  Future<({String? error, File? tempFile, List<String>? runArgs})>
  _prepareBoardApply(
    YoloitCliTool tool,
    Map<String, Object?> normalized,
    List<String> cliArgs,
    ChatRuntimeContext? runtimeContext,
  ) async {
    final yaml = normalized['yaml']?.toString().trim();
    if (yaml == null || yaml.isEmpty) {
      return (error: null, tempFile: null, runArgs: null);
    }
    final tempFile = File(
      '${Directory.systemTemp.path}/yoloit_apply_'
      '${DateTime.now().millisecondsSinceEpoch}.yaml',
    );
    await tempFile.writeAsString(yaml);
    final boardArg =
        cliArgs.length > 1
            ? cliArgs[1]
            : _firstNotEmpty(
              runtimeContext?.boardId,
              runtimeContext?.boardName,
            );
    if (boardArg == null || boardArg.trim().isEmpty) {
      return (
        error: jsonEncode(<String, Object?>{
          'ok': false,
          'executed': false,
          'error': 'Missing board for board:apply',
        }),
        tempFile: tempFile,
        runArgs: null,
      );
    }
    return (
      error: null,
      tempFile: tempFile,
      runArgs: <String>[tool.command, boardArg, tempFile.path],
    );
  }

  /// Runs the yoloit CLI as a subprocess and wraps its output in the
  /// standard JSON tool response.
  Future<String> _runCliProcess({
    required String executable,
    required List<String> runArgs,
    required int? cliPort,
    required YoloitCliTool tool,
    required String rendered,
  }) async {
    final result = await Process.run(
      executable,
      runArgs.map(_argvQuote).toList(),
      runInShell: false,
      environment:
          cliPort == null
              ? null
              : <String, String>{'YOLOIT_CLI_PORT': '$cliPort'},
    ).timeout(timeout);

    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    var ok = result.exitCode == 0;
    if (ok && stdoutText.isNotEmpty) {
      try {
        final decoded = jsonDecode(stdoutText);
        if (decoded is Map && decoded['ok'] is bool) {
          ok = decoded['ok'] as bool;
        }
      } catch (_) {}
    }

    // Notify the UI so remote boards can be refreshed after mutations.
    if (ok && !_isReadOnlyCommand(tool.command)) {
      try {
        final decoded = jsonDecode(stdoutText) as Map<String, dynamic>?;
        if (decoded?['ok'] == true) {
          BoardEventBus.instance.emit(BoardToolMutationEvent(tool.command));
        }
      } catch (_) {
        // Non-JSON output is fine for some legacy commands; ignore.
      }
    }

    return jsonEncode(<String, Object?>{
      'ok': ok,
      'command': rendered,
      'exitCode': result.exitCode,
      if (stdoutText.isNotEmpty) 'stdout': stdoutText,
      if (stderrText.isNotEmpty) 'stderr': stderrText,
    });
  }

  void _deleteTempFile(File? file) {
    if (file == null) return;
    try {
      if (file.existsSync()) {
        file.deleteSync();
      }
    } catch (_) {}
  }

  static const _readOnlySuffixes = <String>{
    ':get',
    ':list',
    ':events',
    ':cards',
    ':columns',
    ':items',
    ':status',
    ':info',
    ':help',
    ':preview',
    ':read',
    ':search',
    ':snapshot',
    ':diagram',
    ':svg',
    ':screenshot',
    ':export',
    ':history',
    ':messages',
    ':logs',
    ':output',
    ':config',
  };

  /// Commands that never mutate board state, matched by exact name.
  static const _readOnlyExactCommands = <String>{
    'help',
    'get_tools',
    'list_tools',
    'panels',
    'panel',
    'panel:types',
    'search',
    'board',
  };

  /// Read-only command groups: a command is read-only when it starts with
  /// the prefix and ends with one of the listed suffixes.
  static const _readOnlyPrefixRules = <(String, Set<String>)>[
    ('board:', _readOnlySuffixes),
    ('template:', _readOnlySuffixes),
    ('files:', _readOnlySuffixes),
    ('filetree:', _readOnlySuffixes),
    ('code:', {':get'}),
    ('note:', {':get'}),
    ('shape:', {':get'}),
    ('sticky:', {':get'}),
    ('table:', {':get'}),
    ('kanban:', {':columns', ':cards'}),
    ('checklist:', {':items'}),
    ('calendar:', {':events', ':show-event'}),
    ('playlist:', {':list'}),
    ('timer:', {':status'}),
    ('webpage:', {':get', ':title', ':url', ':content'}),
  ];

  bool _isReadOnlyCommand(String command) {
    if (_readOnlyExactCommands.contains(command)) return true;
    for (final (prefix, suffixes) in _readOnlyPrefixRules) {
      if (command.startsWith(prefix) && suffixes.any(command.endsWith)) {
        return true;
      }
    }
    return false;
  }

  List<String> _buildCliArgs(
    YoloitCliTool tool,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) {
    final out = <String>[tool.command];
    final smartPanelGroup = _cliAutoResolvesPanel(tool.group);
    YoloitCliToolParam? panelParamDef;
    for (final param in tool.params) {
      if (param.key == 'panel') {
        panelParamDef = param;
        break;
      }
    }
    final panelValue =
        panelParamDef == null
            ? null
            : _argumentValue(
              panelParamDef,
              arguments,
              runtimeContext,
              tool,
            );
    // Bash smart-parse treats the first positional arg as a panel hint when
    // board is omitted. Injecting board without panel breaks e.g.
    // checklist:check "My Board" "item" → panel="My Board".
    final omitBoardForSmartParse =
        smartPanelGroup && _isMissing(panelValue);

    for (final param in tool.params) {
      if (omitBoardForSmartParse && param.key == 'board') {
        continue;
      }
      final value = _argumentValue(param, arguments, runtimeContext, tool);
      if (_isMissing(value)) {
        _throwIfMissingRequired(tool, param);
        continue;
      }
      _appendParamArgument(out, param, value);
    }
    return out;
  }

  void _throwIfMissingRequired(YoloitCliTool tool, YoloitCliToolParam param) {
    if (param.required &&
        !(_cliAutoResolvesPanel(tool.group) &&
            param.runtimeDefault == YoloitCliRuntimeDefault.panel)) {
      throw ArgumentError(
        'Missing required "${param.key}" for ${tool.command}',
      );
    }
  }

  void _appendParamArgument(
    List<String> out,
    YoloitCliToolParam param,
    Object? value,
  ) {
    if (param.isFlag) {
      _appendFlagArgument(out, param, value);
      return;
    }
    final rendered = _stringifyArgument(param, value);
    if (rendered.trim().isEmpty) return;
    out.add(rendered);
  }

  void _appendFlagArgument(
    List<String> out,
    YoloitCliToolParam param,
    Object? value,
  ) {
    if (param.kind == YoloitCliToolParamKind.boolean) {
      if (_asBool(value)) {
        out.add(param.flag!);
      }
      return;
    }
    final rendered = _resolveTextArgument(param, '$value');
    if (rendered.trim().isEmpty) return;
    out
      ..add(param.flag!)
      ..add(rendered);
  }

  String _stringifyArgument(YoloitCliToolParam param, Object? value) {
    if (value is Map || value is List) {
      return jsonEncode(value);
    }
    return _resolveTextArgument(param, '$value');
  }

  String _resolveTextArgument(YoloitCliToolParam param, String value) {
    if (param.kind != YoloitCliToolParamKind.string) return value;
    if (CliTextArgumentResolver.jsonKeys.contains(param.key)) {
      return CliTextArgumentResolver.resolveJsonParameter(value);
    }
    if (!CliTextArgumentResolver.textKeys.contains(param.key) &&
        param.flag != '--text') {
      return value;
    }
    return CliTextArgumentResolver.resolve(value) ??
        (CliTextArgumentResolver.isClipTextFilePath(value) ? '' : value);
  }

  Object? _argumentValue(
    YoloitCliToolParam param,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
    YoloitCliTool tool,
  ) {
    for (final key in param.lookupKeys) {
      if (arguments.containsKey(key)) {
        return arguments[key];
      }
    }
    return switch (param.runtimeDefault) {
      YoloitCliRuntimeDefault.board => _firstNotEmpty(
        runtimeContext?.boardId,
        runtimeContext?.boardName,
      ),
      YoloitCliRuntimeDefault.panel => _panelDefault(runtimeContext, tool),
      null => _appIdDefault(tool, param),
    };
  }

  Object? _appIdDefault(YoloitCliTool tool, YoloitCliToolParam param) {
    if (tool.group != 'app' || param.key != 'id') return null;
    final active = WidgetAppRegistry.instance.activeIds();
    if (active.length == 1) return active.first;
    return null;
  }

  /// Returns the runtime panel default, but skips chat/assistant panels for
  /// tools that operate on typed panels (note, checklist, kanban). The CLI
  /// auto-resolves the correct panel by type when none is provided.
  Object? _panelDefault(ChatRuntimeContext? ctx, YoloitCliTool tool) {
    if (tool.group == 'ui') return null;
    final id = _firstNotEmpty(ctx?.panelId, ctx?.panelTitle);
    if (id == null) return null;
    if (_cliAutoResolvesPanel(tool.group) &&
        (_isChatPanel(id) || _isChatLikePanelType(ctx?.panelType))) {
      return null;
    }
    return id;
  }

  static bool _isChatPanel(String id) {
    return id.contains('assistant') ||
        id.contains('yolo_badge') ||
        id.contains('yolochat');
  }

  static bool _isChatLikePanelType(String? type) {
    final value = type?.trim();
    return value == 'board.chat' || value == 'board.yolo_assistant';
  }

  /// Tool groups where the CLI auto-resolves the panel by type and the chat
  /// panel should NOT be injected as a fallback.
  static bool _cliAutoResolvesPanel(String group) {
    return group == 'note' ||
        group == 'checklist' ||
        group == 'kanban' ||
        group == 'playlist' ||
        group == 'ui';
  }

  bool _isMissing(Object? value) {
    if (value == null) return true;
    if (value is String) {
      final v = value.trim();
      if (v.isEmpty) return true;
      if (v == '__' || v == '_' || v == '...' || v == 'null' || v == 'none') {
        return true;
      }
    }
    return false;
  }

  bool _asBool(Object? value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final v = value.trim().toLowerCase();
      return v == 'true' || v == 'yes' || v == '1' || v == 'on';
    }
    return false;
  }

  bool _confirmedDestructive(Map<String, Object?> arguments) {
    return _asBool(
      arguments['confirm'] ??
          arguments['cf'] ??
          arguments['confirmed'] ??
          arguments['confirmedByUser'] ??
          arguments['confirmed_by_user'],
    );
  }

  /// Validates the built CLI arguments against obvious schema violations.
  /// Returns an error message or null when valid.
  String? _validateCliArgs(YoloitCliTool tool, List<String> cliArgs) {
    final paramByFlag = <String, YoloitCliToolParam>{
      for (final param in tool.params)
        if (param.flag != null) param.flag!: param,
    };
    final paramsByPosition = tool.params.where((p) => p.flag == null).toList();
    var positionalIndex = 0;
    for (var i = 0; i < cliArgs.length; i++) {
      final arg = cliArgs[i];
      if (arg == tool.command) continue;
      if (paramByFlag.containsKey(arg)) {
        final param = paramByFlag[arg]!;
        if (param.kind == YoloitCliToolParamKind.boolean) {
          // boolean flag has no following value
          continue;
        }
        if (i + 1 >= cliArgs.length) {
          return 'Flag "$arg" for ${tool.command} is missing a value';
        }
        final value = cliArgs[i + 1];
        final error = _validateValue(param, value);
        if (error != null) return error;
        i++;
        continue;
      }
      if (positionalIndex < paramsByPosition.length) {
        final param = paramsByPosition[positionalIndex];
        final error = _validateValue(param, arg);
        if (error != null) return error;
        positionalIndex++;
      }
    }
    return null;
  }

  String? _validateValue(YoloitCliToolParam param, String value) {
    if (_isPlaceholderId(value)) {
      return 'Parameter "${param.key}" looks like a placeholder id: "$value". '
          'Use the actual ${param.key} value.';
    }
    if (param.enumValues.isNotEmpty) {
      final text = value.trim();
      if (!param.enumValues.contains(text)) {
        return 'Invalid value for "${param.key}": "$text". '
            'Allowed: ${param.enumValues.join(', ')}';
      }
    }
    if (param.kind == YoloitCliToolParamKind.number) {
      if (num.tryParse(value.trim()) == null) {
        return 'Parameter "${param.key}" must be a number, got "$value"';
      }
    }
    return null;
  }

  /// Detects values that look like LLM-invented identifiers such as
  /// "yoloit_board_grid" or "board_terminal_12345" being passed as a board,
  /// panel, or session id.
  bool _isPlaceholderId(String value) {
    final lower = value.trim().toLowerCase();
    if (lower.startsWith('yoloit_')) return true;
    if (RegExp(r'^board_[a-z_]+_\d+$').hasMatch(lower)) return true;
    return false;
  }

  String? _firstNotEmpty(String? first, String? second) {
    final a = first?.trim();
    if (a != null && a.isNotEmpty && a != 'unknown') return a;
    final b = second?.trim();
    if (b != null && b.isNotEmpty && b != 'unknown') return b;
    return null;
  }

  String _renderCommand(List<String> args) {
    return ['yoloit', ...args].map(_shellQuote).join(' ');
  }

  String _shellQuote(String value) {
    if (RegExp(r'^[a-zA-Z0-9_./:=@-]+$').hasMatch(value)) {
      return value;
    }
    return "'${value.replaceAll("'", "'\\''")}'";
  }

  /// Quotes an argument so it survives being passed to the bash script via
  /// [Process.run] with [runInShell] false. The script parses positional
  /// arguments with `"$1"`, so JSON payloads and titles with spaces must be
  /// enclosed in double quotes and have their inner double quotes escaped.
  String _argvQuote(String value) {
    if (RegExp(r'^[a-zA-Z0-9_./:=@-]+$').hasMatch(value)) {
      return value;
    }
    return '"${value.replaceAll('"', '\\"')}"';
  }

  String _resolveYoloitExecutable() {
    final explicit = executablePath ?? Platform.environment['YOLOIT_CLI_PATH'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final installed = CliServer.installedCliExecutable;
    if (installed != null) {
      return installed.path;
    }

    final checked = <String>[];
    final found = findYoloitCliScript(checked: checked);
    if (found != null) {
      return found;
    }
    throw StateError(
      'Cannot find tools/yoloit. Checked: ${checked.join(', ')}',
    );
  }
}

YoloitToolExecutor createPlatformToolExecutor() =>
    YoloitCliToolExecutor();
