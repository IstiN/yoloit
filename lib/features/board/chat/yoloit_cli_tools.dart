import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:path/path.dart' as p;
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

enum YoloitCliToolParamKind { string, number, boolean }

enum YoloitCliRuntimeDefault { board, panel }

class YoloitCliToolParam {
  const YoloitCliToolParam({
    required this.key,
    required this.description,
    this.required = false,
    this.flag,
    this.kind = YoloitCliToolParamKind.string,
    this.aliases = const <String>[],
    this.runtimeDefault,
    this.enumValues = const <String>[],
    this.shortKey,
  });

  final String key;
  final String description;
  final bool required;
  final String? flag;
  final YoloitCliToolParamKind kind;
  final List<String> aliases;
  final YoloitCliRuntimeDefault? runtimeDefault;
  final List<String> enumValues;
  final String? shortKey;

  bool get isFlag => flag != null;
  String get compactKey => shortKey ?? key;

  Map<String, Object?> toJsonSchema() {
    final type = switch (kind) {
      YoloitCliToolParamKind.string => 'string',
      YoloitCliToolParamKind.number => 'number',
      YoloitCliToolParamKind.boolean => 'boolean',
    };
    return <String, Object?>{
      'type': type,
      'description': description,
      if (enumValues.isNotEmpty) 'enum': enumValues,
    };
  }

  Map<String, Object?> toCompactJsonSchema() {
    final type = switch (kind) {
      YoloitCliToolParamKind.string => 'string',
      YoloitCliToolParamKind.number => 'number',
      YoloitCliToolParamKind.boolean => 'boolean',
    };
    return <String, Object?>{
      'type': type,
      if (enumValues.isNotEmpty) 'enum': enumValues,
    };
  }
}

class YoloitCliTool {
  const YoloitCliTool({
    required this.command,
    required this.description,
    this.alias,
    this.group = 'app',
    this.params = const <YoloitCliToolParam>[],
    this.destructive = false,
  });

  final String command;
  final String description;
  final String? alias;
  final String group;
  final List<YoloitCliToolParam> params;
  final bool destructive;

  String get functionName =>
      alias ?? YoloitCliToolCatalog.functionNameFor(command);
  String get fullFunctionName => YoloitCliToolCatalog.functionNameFor(command);

  flm.LocalTool toLocalTool() {
    final isCompact = alias != null;
    final properties = <String, Object?>{};
    final requiredKeys = <String>[];
    for (final param in params) {
      final propKey = isCompact ? param.compactKey : param.key;
      properties[propKey] =
          isCompact ? param.toCompactJsonSchema() : param.toJsonSchema();
      if (param.required) requiredKeys.add(propKey);
    }
    if (destructive) {
      final confirmKey = isCompact ? 'cf' : 'confirm';
      properties[confirmKey] =
          isCompact
              ? const <String, Object?>{'type': 'boolean'}
              : const <String, Object?>{
                'type': 'boolean',
                'description':
                    'Set true only after the user explicitly confirmed this destructive action.',
              };
    }
    final schema = <String, Object?>{
      'type': 'object',
      'properties': properties,
      if (!isCompact) 'additionalProperties': false,
      if (requiredKeys.isNotEmpty) 'required': requiredKeys,
    };
    final desc =
        isCompact
            ? description
            : 'yoloit $command — $description.${destructive ? ' Ask for confirmation before using it.' : ''}';
    return flm.LocalTool.function(
      name: functionName,
      description: desc,
      parametersJsonSchema: schema,
      metadata: <String, Object?>{
        'command': command,
        'group': group,
        'destructive': destructive,
      },
    );
  }
}

class YoloitCliToolCatalog {
  YoloitCliToolCatalog._();

  static final List<YoloitCliTool> tools = List<YoloitCliTool>.unmodifiable(
    _tools,
  );

  static final List<flm.LocalTool> localTools =
      List<flm.LocalTool>.unmodifiable(<flm.LocalTool>[
        const flm.LocalTool.function(
          name: 'get_tools',
          description: 'List available YoLoIT CLI tools in compact JSON.',
          parametersJsonSchema: <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{},
            'additionalProperties': false,
          },
        ),
        ..._tools.map((tool) => tool.toLocalTool()),
      ]);

  static List<flm.LocalTool> localToolsFor({
    Set<String> disabledFunctionNames = const <String>{},
  }) {
    final disabled = normalizeFunctionNames(disabledFunctionNames);
    return List<flm.LocalTool>.unmodifiable(<flm.LocalTool>[
      const flm.LocalTool.function(
        name: 'get_tools',
        description: 'List available YoLoIT CLI tools in compact JSON.',
        parametersJsonSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      for (final tool in _tools)
        if (!disabled.contains(tool.functionName) &&
            !disabled.contains(tool.fullFunctionName))
          tool.toLocalTool(),
    ]);
  }

  static YoloitCliTool? byFunctionName(String name) {
    final resolvedName = _functionAliases[name] ?? name;
    if (name == 'get_tools' || name == 'list_tools') {
      return null;
    }
    for (final tool in _tools) {
      if (tool.functionName == resolvedName ||
          tool.functionName == name ||
          tool.fullFunctionName == resolvedName ||
          tool.alias == name) {
        return tool;
      }
    }
    return null;
  }

  static const Map<String, String> _functionAliases = <String, String>{
    'yoloit_board_show': 'yoloit_board',
    'yoloit_board_details': 'yoloit_board',
  };

  static String functionNameFor(String command) {
    final sanitized = command.replaceAll(RegExp(r'[^a-zA-Z0-9]+'), '_');
    return 'yoloit_$sanitized';
  }

  static String compactToolsJson({
    Set<String> disabledFunctionNames = const <String>{},
  }) {
    final disabled = normalizeFunctionNames(disabledFunctionNames);
    return jsonEncode(<String, Object?>{
      'tools': [
        for (final tool in _tools)
          if (!disabled.contains(tool.functionName) &&
              !disabled.contains(tool.fullFunctionName))
            <String, Object?>{
              'name': tool.functionName,
              'command': 'yoloit ${tool.command}',
              'description': tool.description,
              'params': [
                for (final param in tool.params)
                  <String, Object?>{
                    'key': param.key,
                    'required': param.required,
                    if (param.flag != null) 'flag': param.flag,
                  },
              ],
            },
      ],
    });
  }

  static Set<String> normalizeFunctionNames(Iterable<String> values) {
    final out = <String>{};
    for (final raw in values) {
      final name = _normalizeFunctionName(raw);
      if (name.isEmpty) continue;
      out.add(name);
      final resolvedAlias = _functionAliases[name];
      if (resolvedAlias != null) {
        out.add(resolvedAlias);
      }
      final tool = byFunctionName(name);
      if (tool != null) {
        out
          ..add(tool.functionName)
          ..add(tool.fullFunctionName);
      }
    }
    return out;
  }

  static bool isFunctionDisabled({
    required String functionName,
    required Set<String> disabledFunctionNames,
  }) {
    if (disabledFunctionNames.isEmpty) return false;
    final normalized = normalizeFunctionNames(disabledFunctionNames);
    if (normalized.contains(functionName)) return true;
    final tool = byFunctionName(functionName);
    if (tool == null) return false;
    return normalized.contains(tool.functionName) ||
        normalized.contains(tool.fullFunctionName);
  }

  static String _normalizeFunctionName(String value) => value.trim();
}

class YoloitCliToolArgumentNormalizer {
  YoloitCliToolArgumentNormalizer._();

  static String normalizeFunctionName({
    required String functionName,
    required String userMessage,
  }) {
    final text = userMessage.toLowerCase();
    if (functionName == 'yoloit_panel_help' &&
        (text.contains('details') || text.contains('content')) &&
        !text.contains('actions') &&
        !text.contains('available')) {
      return 'yoloit_panel';
    }
    if (functionName == 'yoloit_note_create' &&
        ((text.contains('create') && text.contains('panel')) ||
            text.contains('замет'))) {
      return 'yoloit_panel_create';
    }
    if (functionName == 'yoloit_board_focus' && text.contains('panel')) {
      return 'yoloit_panel_focus';
    }
    if (functionName == 'yoloit_panel_focus' &&
        text.contains('show') &&
        text.contains('panel') &&
        !text.contains('focus')) {
      return 'yoloit_panel_show';
    }
    if (functionName == 'yoloit_note_replace') {
      return 'yoloit_note';
    }
    if (functionName == 'yoloit_reload' && text.contains('restart')) {
      return 'yoloit_restart';
    }
    return functionName;
  }

  static Map<String, Object?> normalize({
    required String functionName,
    required Map<String, Object?> arguments,
    required String userMessage,
    ChatRuntimeContext? runtimeContext,
  }) {
    final normalized = Map<String, Object?>.from(arguments);
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    if (tool?.command == 'panel:create' && _isMissing(normalized['type'])) {
      final type = _inferPanelType(userMessage);
      if (type != null) {
        normalized['type'] = type;
      }
    }
    _normalizeBoardArguments(tool?.command, normalized, userMessage);
    _normalizePanelArguments(tool?.command, normalized, userMessage);
    _normalizeLinkArguments(tool?.command, normalized, userMessage);
    _normalizeRuntimeContextArguments(
      tool?.command,
      normalized,
      userMessage,
      runtimeContext,
    );
    if (tool?.destructive == true &&
        _isMissing(normalized['confirm']) &&
        _mentionsConfirmation(userMessage)) {
      normalized['confirm'] = true;
    }
    if (tool?.command == 'run:input' &&
        _isMissing(normalized['enter']) &&
        userMessage.toLowerCase().contains('enter')) {
      normalized['enter'] = true;
    }
    if (tool?.command == 'run:attach' &&
        _isMissing(normalized['any']) &&
        (userMessage.toLowerCase().contains('allow stopped') ||
            userMessage.toLowerCase().contains('allowing stopped'))) {
      normalized['any'] = true;
    }
    return normalized;
  }

  static void _normalizeBoardArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command == 'board:zoom' && _isMissing(normalized['scale'])) {
      final scale = _firstNumberAfter(userMessage, RegExp(r'\bzoom\b|\bto\b'));
      if (scale != null) normalized['scale'] = scale;
    }
    if (command == 'board:arrange') {
      final text = userMessage.toLowerCase();
      if (_isMissing(normalized['direction'])) {
        if (text.contains('right')) {
          normalized['direction'] = 'right';
        } else if (text.contains('down')) {
          normalized['direction'] = 'down';
        }
      }
      if (_isMissing(normalized['h_spacing'])) {
        final value = _numberAfterLabel(
          userMessage,
          RegExp(r'horizontal spacing|h spacing'),
        );
        if (value != null) normalized['h_spacing'] = value;
      }
      if (_isMissing(normalized['v_spacing'])) {
        final value = _numberAfterLabel(
          userMessage,
          RegExp(r'vertical spacing|v spacing'),
        );
        if (value != null) normalized['v_spacing'] = value;
      }
    }
    if (command == 'board:translate') {
      if (_isMissing(normalized['x'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\bx\b'));
        if (value != null) normalized['x'] = value;
      }
      if (_isMissing(normalized['y'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\by\b'));
        if (value != null) normalized['y'] = value;
      }
    }
    if (command == 'board:delete' && _isMissing(normalized['id_or_name'])) {
      final boardName = _extractNamedTarget(
        userMessage,
        RegExp(r'delete board'),
      );
      if (boardName != null) normalized['id_or_name'] = boardName;
    }
  }

  static void _normalizePanelArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command == 'panel:move') {
      if (_isMissing(normalized['x'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\bx\b'));
        if (value != null) normalized['x'] = value;
      }
      if (_isMissing(normalized['y'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\by\b'));
        if (value != null) normalized['y'] = value;
      }
    }
    if (command == 'panel:resize') {
      if (_isMissing(normalized['width'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\bwidth\b'));
        if (value != null) normalized['width'] = value;
      }
      if (_isMissing(normalized['height'])) {
        final value = _numberAfterLabel(userMessage, RegExp(r'\bheight\b'));
        if (value != null) normalized['height'] = value;
      }
    }
    if (command == 'panel:create' && _isMissing(normalized['title'])) {
      final title = _extractTitle(userMessage);
      if (title != null) normalized['title'] = title;
    }
    if (command != null &&
        (command == 'panel' || command.startsWith('panel:')) &&
        _isMissing(normalized['panel']) &&
        !_isMissing(normalized['id_or_name'])) {
      normalized['panel'] = normalized['id_or_name'];
      normalized.remove('id_or_name');
    }
    if ((command == 'panel:focus' || command == 'panel:show') &&
        _isMissing(normalized['panel'])) {
      final panelName = _extractNamedTarget(
        userMessage,
        RegExp(r'panel named|panel called|panel titled'),
      );
      if (panelName != null) normalized['panel'] = panelName;
    }
    if (command == 'panel:delete' && _isMissing(normalized['panel'])) {
      final panelName = _extractNamedTarget(
        userMessage,
        RegExp(r'delete panel'),
      );
      if (panelName != null) normalized['panel'] = panelName;
    }
  }

  static void _normalizeLinkArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command == 'link:delete' && _isMissing(normalized['link_id'])) {
      final linkId = _extractNamedTarget(userMessage, RegExp(r'delete link'));
      if (linkId != null) normalized['link_id'] = linkId;
    }
  }

  static void _normalizeRuntimeContextArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
    ChatRuntimeContext? runtimeContext,
  ) {
    if (command == null || runtimeContext == null) return;
    if (!_usesPanelArgument(command)) {
      return;
    }
    final panelId = runtimeContext.panelId?.trim();
    if (panelId == null || panelId.isEmpty) return;
    final panelValue = normalized['panel'];
    if (_mentionsCurrentPanel(userMessage) ||
        _looselySameIdentifier(panelValue, panelId) ||
        _looselySameIdentifier(panelValue, runtimeContext.panelTitle)) {
      normalized['panel'] = panelId;
    }
  }

  static bool _usesPanelArgument(String command) {
    return command == 'panel' ||
        command.startsWith('panel:') ||
        command == 'do' ||
        command == 'note' ||
        command.startsWith('note:') ||
        command.startsWith('checklist:') ||
        command.startsWith('kanban:') ||
        command.startsWith('run:') ||
        command == 'play' ||
        command == 'web:open';
  }

  static String? _inferPanelType(String userMessage) {
    final text = userMessage.toLowerCase();
    if (text.contains('kanban')) return 'board.kanban';
    if (text.contains('run panel') ||
        text.contains('dev server') ||
        text.contains('terminal') ||
        text.contains('console')) {
      return 'board.run';
    }
    if (text.contains('markdown') ||
        text.contains('note') ||
        text.contains('замет')) {
      return 'board.note.markdown';
    }
    if (text.contains('канбан')) return 'board.kanban';
    if (text.contains('терминал') || text.contains('консол')) {
      return 'board.run';
    }
    if (text.contains('чеклист')) return 'board.checklist';
    if (text.contains('чат')) return 'board.chat';
    if (text.contains('checklist')) return 'board.checklist';
    if (text.contains('webpage') || text.contains('web panel')) {
      return 'board.webpage';
    }
    if (text.contains('playlist') || text.contains('media')) {
      return 'board.playlist';
    }
    if (text.contains('chat panel')) return 'board.chat';
    return null;
  }

  static bool _isMissing(Object? value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
    return false;
  }

  static bool _mentionsConfirmation(String userMessage) {
    final text = userMessage.toLowerCase();
    return text.contains('i confirm') ||
        text.contains('confirmed') ||
        text.contains('confirm this') ||
        text.contains('confirm discarding');
  }

  static num? _firstNumberAfter(String userMessage, RegExp marker) {
    final match = marker.firstMatch(userMessage.toLowerCase());
    if (match == null) return _numberAfterLabel(userMessage, RegExp(''));
    return _parseNumber(userMessage.substring(match.end));
  }

  static num? _numberAfterLabel(String userMessage, RegExp label) {
    final match = label.firstMatch(userMessage.toLowerCase());
    final source =
        match == null ? userMessage : userMessage.substring(match.end);
    return _parseNumber(source);
  }

  static num? _parseNumber(String source) {
    final match = RegExp(r'-?\d+(?:\.\d+)?').firstMatch(source);
    if (match == null) return null;
    final value = match.group(0)!;
    return value.contains('.') ? double.parse(value) : int.parse(value);
  }

  static String? _extractAfterPhrase(String userMessage, RegExp phrase) {
    final match = phrase.firstMatch(userMessage.toLowerCase());
    if (match == null) return null;
    final raw = userMessage.substring(match.end);
    final beforeConfirm =
        raw
            .split(RegExp(r';|,?\s+i confirm\b', caseSensitive: false))
            .first
            .trim();
    return beforeConfirm.isEmpty ? null : beforeConfirm;
  }

  static String? _extractTitle(String userMessage) {
    final match = RegExp(
      r'(?:titled|named|called)\s+(.+?)(?:\.|$|\s+on this board|\s+for this board)',
      caseSensitive: false,
    ).firstMatch(userMessage);
    final title = match?.group(1)?.trim();
    if (title != null && title.isNotEmpty) return title;
    if (RegExp(
      r'\b(note|markdown)\b|замет',
      caseSensitive: false,
    ).hasMatch(userMessage)) {
      return 'Note';
    }
    return null;
  }

  static String? _extractNamedTarget(String userMessage, RegExp phrase) {
    final raw = _extractAfterPhrase(userMessage, phrase);
    if (raw == null) return null;
    final cleaned =
        raw
            .replaceFirst(
              RegExp(r'\s+on (this|the current) board$', caseSensitive: false),
              '',
            )
            .replaceFirst(
              RegExp(
                r'\s+from (this|the current) board$',
                caseSensitive: false,
              ),
              '',
            )
            .trim();
    return cleaned.isEmpty ? null : cleaned;
  }

  static bool _mentionsCurrentPanel(String userMessage) {
    final text = userMessage.toLowerCase();
    return text.contains('current panel') ||
        text.contains('current note') ||
        text.contains('current run panel') ||
        (text.contains('current') && text.contains('panel')) ||
        (text.contains('this') && text.contains('panel')) ||
        text.contains('this panel');
  }

  static bool _looselySameIdentifier(Object? first, String? second) {
    if (first == null || second == null) return false;
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return normalize('$first') == normalize(second);
  }
}

abstract interface class YoloitToolExecutor {
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
  });
}

class YoloitCliToolExecutor implements YoloitToolExecutor {
  YoloitCliToolExecutor({
    this.execute = true,
    this.executablePath,
    this.timeout = const Duration(seconds: 30),
  });

  final bool execute;
  final String? executablePath;
  final Duration timeout;

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
  }) async {
    if (functionName == 'get_tools' || functionName == 'list_tools') {
      return YoloitCliToolCatalog.compactToolsJson();
    }
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    if (tool == null) {
      return jsonEncode(<String, Object?>{
        'ok': false,
        'error': 'Unknown YoLoIT tool: $functionName',
      });
    }

    final cliArgs = _buildCliArgs(tool, arguments, runtimeContext);
    final rendered = _renderCommand(cliArgs);
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

    final executable = executablePath ?? _resolveYoloitExecutable();
    final cliPort = CliServer.instance.port;
    final result = await Process.run(
      executable,
      cliArgs,
      runInShell: false,
      environment:
          cliPort == null
              ? null
              : <String, String>{'YOLOIT_CLI_PORT': '$cliPort'},
    ).timeout(timeout);

    final stdoutText = result.stdout.toString().trim();
    final stderrText = result.stderr.toString().trim();
    return jsonEncode(<String, Object?>{
      'ok': result.exitCode == 0,
      'command': rendered,
      'exitCode': result.exitCode,
      if (stdoutText.isNotEmpty) 'stdout': stdoutText,
      if (stderrText.isNotEmpty) 'stderr': stderrText,
    });
  }

  List<String> _buildCliArgs(
    YoloitCliTool tool,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) {
    final out = <String>[tool.command];
    for (final param in tool.params) {
      final value = _argumentValue(param, arguments, runtimeContext);
      if (_isMissing(value)) {
        if (param.required) {
          throw ArgumentError(
            'Missing required "${param.key}" for ${tool.command}',
          );
        }
        continue;
      }
      if (param.isFlag) {
        if (param.kind == YoloitCliToolParamKind.boolean) {
          if (_asBool(value)) {
            out.add(param.flag!);
          }
        } else {
          out
            ..add(param.flag!)
            ..add('$value');
        }
        continue;
      }
      out.add('$value');
    }
    return out;
  }

  Object? _argumentValue(
    YoloitCliToolParam param,
    Map<String, Object?> arguments,
    ChatRuntimeContext? runtimeContext,
  ) {
    if (param.shortKey != null && arguments.containsKey(param.shortKey!)) {
      return arguments[param.shortKey!];
    }
    if (arguments.containsKey(param.key)) {
      return arguments[param.key];
    }
    for (final alias in param.aliases) {
      if (arguments.containsKey(alias)) {
        return arguments[alias];
      }
    }
    return switch (param.runtimeDefault) {
      YoloitCliRuntimeDefault.board => _firstNotEmpty(
        runtimeContext?.boardId,
        runtimeContext?.boardName,
      ),
      YoloitCliRuntimeDefault.panel => _firstNotEmpty(
        runtimeContext?.panelId,
        runtimeContext?.panelTitle,
      ),
      null => null,
    };
  }

  bool _isMissing(Object? value) {
    if (value == null) return true;
    if (value is String && value.trim().isEmpty) return true;
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

  String _resolveYoloitExecutable() {
    final explicit = executablePath ?? Platform.environment['YOLOIT_CLI_PATH'];
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }

    final checked = <String>[];
    final roots = <String?>[
      Directory.current.path,
      Platform.environment['PWD'],
      Platform.environment['YOLOIT_PROJECT_ROOT'],
      Platform.environment['PROJECT_DIR'],
      p.dirname(Platform.resolvedExecutable),
    ];
    final seen = <String>{};
    for (final root in roots) {
      if (root == null || root.trim().isEmpty) continue;
      var dir = Directory(p.normalize(p.absolute(root.trim())));
      for (var i = 0; i < 16; i++) {
        final candidates = <File>[
          File(p.join(dir.path, 'tools', 'yoloit')),
          File(p.join(dir.path, 'yoloit', 'tools', 'yoloit')),
        ];
        for (final candidate in candidates) {
          if (!seen.add(candidate.path)) continue;
          checked.add(candidate.path);
          if (candidate.existsSync()) {
            return candidate.path;
          }
        }
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    throw StateError(
      'Cannot find tools/yoloit. Checked: ${checked.join(', ')}',
    );
  }
}

YoloitCliToolParam _p(
  String key,
  String description, {
  bool required = false,
  String? flag,
  YoloitCliToolParamKind kind = YoloitCliToolParamKind.string,
  List<String> aliases = const <String>[],
  YoloitCliRuntimeDefault? runtimeDefault,
  List<String> enumValues = const <String>[],
  String? shortKey,
}) {
  return YoloitCliToolParam(
    key: key,
    description: description,
    required: required,
    flag: flag,
    kind: kind,
    aliases: aliases,
    runtimeDefault: runtimeDefault,
    enumValues: enumValues,
    shortKey: shortKey,
  );
}

YoloitCliToolParam _boardParam([String key = 'board']) {
  return _p(
    key,
    'Board id or name. Defaults to the current board.',
    required: true,
    aliases: const <String>[
      'board',
      'id_or_name',
      'board_id',
      'board_name',
      'id',
    ],
    runtimeDefault: YoloitCliRuntimeDefault.board,
    shortKey: 'b',
  );
}

YoloitCliToolParam _panelParam([String key = 'panel']) {
  return _p(
    key,
    'Panel id or title. Defaults to the current chat panel.',
    required: true,
    aliases: const <String>['panel_id', 'panel_title', 'id'],
    runtimeDefault: YoloitCliRuntimeDefault.panel,
    shortKey: 'p',
  );
}

YoloitCliToolParam _panelTypeParam() {
  return _p(
    'type',
    'Required panel type id. Use exactly: board.note.markdown for markdown/note panels, board.kanban for kanban panels, board.run for Run/dev-server/terminal panels, board.chat for chat panels, board.checklist for checklist panels, board.webpage for web panels, board.playlist for media panels.',
    required: true,
    aliases: const <String>['panel_type', 'kind'],
    enumValues: const <String>[
      'board.note.markdown',
      'board.kanban',
      'board.run',
      'board.chat',
      'board.checklist',
      'board.webpage',
      'board.playlist',
    ],
    shortKey: 'tp',
  );
}

// Compact alias system: 67 tools with short aliases + shortKey params reduce
// local LLM tool schema token count by ~60-70% compared to verbose format.
final List<YoloitCliTool> _tools = <YoloitCliTool>[
  YoloitCliTool(
    command: 'help',
    alias: 'hlp',
    description: 'Show CLI help',
    group: 'app',
    params: <YoloitCliToolParam>[
      _p(
        'format',
        'short, detailed, mermaid, or tools',
        flag: '--format',
        shortKey: 'fmt',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'reload',
    alias: 'rl',
    description: 'Hot reload the running Flutter app',
    group: 'app',
  ),
  YoloitCliTool(
    command: 'restart',
    alias: 'rs',
    description: 'Hot restart the running Flutter app',
    group: 'app',
  ),
  YoloitCliTool(
    command: 'boards',
    alias: 'bls',
    description: 'List all boards',
    group: 'board',
  ),
  YoloitCliTool(
    command: 'board',
    alias: 'bgt',
    description: 'Show board details',
    group: 'board',
    params: <YoloitCliToolParam>[_boardParam('id_or_name')],
  ),
  YoloitCliTool(
    command: 'board:create',
    alias: 'bmk',
    description: 'Create a board',
    group: 'board',
    params: <YoloitCliToolParam>[
      _p('name', 'New board name', required: true, shortKey: 'n'),
    ],
  ),
  YoloitCliTool(
    command: 'board:rename',
    alias: 'brn',
    description: 'Rename a board',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p(
        'new_name',
        'New board name',
        required: true,
        aliases: const ['new'],
        shortKey: 'nn',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:delete',
    alias: 'bdl',
    description: 'Delete a board',
    group: 'board',
    destructive: true,
    params: <YoloitCliToolParam>[_boardParam('id_or_name')],
  ),
  YoloitCliTool(
    command: 'board:focus',
    alias: 'bfc',
    description: 'Focus a board in the UI',
    group: 'board',
    params: <YoloitCliToolParam>[_boardParam('id_or_name')],
  ),
  YoloitCliTool(
    command: 'board:apply',
    alias: 'bap',
    description: 'Apply YAML bulk operations',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p('file', "YAML file path or '-' for stdin"),
    ],
  ),
  YoloitCliTool(
    command: 'board:snapshot',
    alias: 'bsn',
    description: 'Text snapshot of board layout',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p('format', 'md or mermaid', flag: '--format', shortKey: 'fmt'),
    ],
  ),
  YoloitCliTool(
    command: 'board:diagram',
    alias: 'bdg',
    description: 'Mermaid-focused board diagram',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p('format', 'mermaid or md', flag: '--format', shortKey: 'fmt'),
    ],
  ),
  YoloitCliTool(
    command: 'board:screenshot',
    alias: 'bsc',
    description: 'Save PNG screenshot',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p(
        'file_png',
        'Output PNG path',
        aliases: const ['file', 'path'],
        shortKey: 'fp',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:svg',
    alias: 'bsv',
    description: 'Export SVG layout',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p(
        'file_svg',
        'Output SVG path',
        aliases: const ['file', 'path'],
        shortKey: 'fs',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:zoom',
    alias: 'bzm',
    description: 'Set board zoom scale',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p(
        'scale',
        'Zoom scale',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'sc',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:fit',
    alias: 'bft',
    description: 'Fit board to viewport',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p(
        'size',
        'Viewport size like 1280x800',
        aliases: const ['wxh'],
        shortKey: 'sz',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:arrange',
    alias: 'bar',
    description: 'Arrange visible panels',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('id_or_name'),
      _p('direction', 'right or down', shortKey: 'dir'),
      _p(
        'h_spacing',
        'Horizontal spacing',
        kind: YoloitCliToolParamKind.number,
        aliases: const <String>['horizontal_spacing', 'horizontal', 'hSpacing'],
        shortKey: 'hs',
      ),
      _p(
        'v_spacing',
        'Vertical spacing',
        kind: YoloitCliToolParamKind.number,
        aliases: const <String>['vertical_spacing', 'vertical', 'vSpacing'],
        shortKey: 'vs',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'board:translate',
    alias: 'btr',
    description: 'Move board viewport',
    group: 'board',
    params: <YoloitCliToolParam>[
      _boardParam('board'),
      _p(
        'x',
        'Viewport x',
        required: true,
        kind: YoloitCliToolParamKind.number,
      ),
      _p(
        'y',
        'Viewport y',
        required: true,
        kind: YoloitCliToolParamKind.number,
      ),
    ],
  ),
  YoloitCliTool(
    command: 'panels',
    alias: 'pls',
    description: 'List panels on a board',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam()],
  ),
  YoloitCliTool(
    command: 'panel',
    alias: 'pgt',
    description: 'Show panel details and content',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:help',
    alias: 'phx',
    description: 'Show dynamic panel actions',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:create',
    alias: 'pmk',
    description:
        'Create a panel. Always include the exact panel type id in `type`.',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelTypeParam(),
      _p('title', 'Panel title', required: true, shortKey: 't'),
    ],
  ),
  YoloitCliTool(
    command: 'panel:rename',
    alias: 'prn',
    description: 'Rename a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'new_title',
        'New title',
        required: true,
        aliases: const ['new'],
        shortKey: 'nt',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'panel:move',
    alias: 'pmv',
    description: 'Move a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('x', 'New x', required: true, kind: YoloitCliToolParamKind.number),
      _p('y', 'New y', required: true, kind: YoloitCliToolParamKind.number),
    ],
  ),
  YoloitCliTool(
    command: 'panel:resize',
    alias: 'psz',
    description: 'Resize a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'width',
        'New width',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'w',
      ),
      _p(
        'height',
        'New height',
        required: true,
        kind: YoloitCliToolParamKind.number,
        shortKey: 'h',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'panel:delete',
    alias: 'pdl',
    description: 'Delete a panel',
    group: 'panel',
    destructive: true,
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:focus',
    alias: 'pfc',
    description: 'Focus a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:color',
    alias: 'pcl',
    description: 'Set or clear panel color',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('color', 'Color value or clear', required: true, shortKey: 'cl'),
    ],
  ),
  YoloitCliTool(
    command: 'panel:hide',
    alias: 'phd',
    description: 'Hide a panel',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:show',
    alias: 'psh',
    description: 'Show a hidden panel',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'panel:types',
    alias: 'ptp',
    description: 'List available panel types',
    group: 'panel',
    params: <YoloitCliToolParam>[_boardParam()],
  ),
  YoloitCliTool(
    command: 'do',
    alias: 'pdo',
    description: 'Execute a panel action',
    group: 'panel',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('action', 'Action from panel:help', required: true, shortKey: 'a'),
      _p('json', 'Optional JSON body', shortKey: 'j'),
    ],
  ),
  YoloitCliTool(
    command: 'run:list',
    alias: 'rls',
    description:
        'List run configs and sessions. If the user names a panel, pass that exact panel title.',
    group: 'run',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'run:input',
    alias: 'rin',
    description: 'Send stdin to a run session',
    group: 'run',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'session',
        'Session id, config id, or name',
        required: true,
        shortKey: 's',
      ),
      _p('text', 'Input text', required: true, shortKey: 'tx'),
      _p(
        'enter',
        'Append newline',
        flag: '--enter',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'e',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'run:output',
    alias: 'rot',
    description: 'Read run session output',
    group: 'run',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),
  YoloitCliTool(
    command: 'run:detach',
    alias: 'rdt',
    description: 'Detach run session from panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),
  YoloitCliTool(
    command: 'run:attach',
    alias: 'rat',
    description: 'Attach run console to a session',
    group: 'run',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('session', 'Session id, config id, or name', shortKey: 's'),
      _p(
        'any',
        'Allow stopped sessions',
        flag: '--any',
        kind: YoloitCliToolParamKind.boolean,
        shortKey: 'ay',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'run:popout',
    alias: 'rpo',
    description: 'Open detached session in a new Run panel',
    group: 'run',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('session', 'Session id, config id, or name', shortKey: 's'),
    ],
  ),
  YoloitCliTool(
    command: 'models:list',
    alias: 'mls',
    description: 'List local AI model states',
    group: 'models',
  ),
  YoloitCliTool(
    command: 'models:download',
    alias: 'mdl',
    description: 'Manage a local model download/install state',
    group: 'models',
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:resume',
    alias: 'mrs',
    description: 'Manage a local model download/install state',
    group: 'models',
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:pause',
    alias: 'mps',
    description: 'Manage a local model download/install state',
    group: 'models',
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:cancel',
    alias: 'mcn',
    description: 'Manage a local model download/install state',
    group: 'models',
    destructive: true,
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:stop',
    alias: 'mst',
    description: 'Manage a local model download/install state',
    group: 'models',
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:delete',
    alias: 'mdt',
    description: 'Manage a local model download/install state',
    group: 'models',
    destructive: true,
    params: <YoloitCliToolParam>[
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'models:select',
    alias: 'msl',
    description: 'Select active local chat or ASR model',
    group: 'models',
    params: <YoloitCliToolParam>[
      _p('kind', 'chat or asr', required: true, shortKey: 'k'),
      _p(
        'model_id',
        'Local model id',
        required: true,
        aliases: const ['id'],
        shortKey: 'mid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'yolochat:panels',
    alias: 'cls',
    description: 'List all board.chat panels',
    group: 'yolochat',
  ),
  YoloitCliTool(
    command: 'yolochat:send',
    alias: 'csd',
    description: 'Send a message to a YoLo chat panel',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      _p('text', 'Message text', required: true, shortKey: 'tx'),
      _p(
        'board',
        'Target board',
        flag: '--board',
        runtimeDefault: YoloitCliRuntimeDefault.board,
        shortKey: 'b',
      ),
      _p(
        'panel',
        'Target chat panel',
        flag: '--panel',
        runtimeDefault: YoloitCliRuntimeDefault.panel,
        shortKey: 'p',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'yolochat:messages',
    alias: 'cms',
    description: 'Read YoLo chat messages',
    group: 'yolochat',
    params: <YoloitCliToolParam>[
      _p(
        'board',
        'Target board',
        flag: '--board',
        runtimeDefault: YoloitCliRuntimeDefault.board,
        shortKey: 'b',
      ),
      _p(
        'panel',
        'Target chat panel',
        flag: '--panel',
        runtimeDefault: YoloitCliRuntimeDefault.panel,
        shortKey: 'p',
      ),
      _p(
        'limit',
        'Max messages',
        flag: '--limit',
        kind: YoloitCliToolParamKind.number,
        shortKey: 'lim',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'links',
    alias: 'lls',
    description: 'List links on a board',
    group: 'link',
    params: <YoloitCliToolParam>[_boardParam()],
  ),
  YoloitCliTool(
    command: 'link:create',
    alias: 'lmk',
    description: 'Create panel link',
    group: 'link',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _p('from', 'Source panel id or title', required: true, shortKey: 'fr'),
      _p('to', 'Target panel id or title', required: true),
    ],
  ),
  YoloitCliTool(
    command: 'link:delete',
    alias: 'ldl',
    description: 'Delete panel link',
    group: 'link',
    destructive: true,
    params: <YoloitCliToolParam>[
      _boardParam(),
      _p(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'link:style',
    alias: 'lst',
    description: 'Set link style and geometry',
    group: 'link',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _p(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
      _p('style', 'arrow or line', required: true, shortKey: 'st'),
      _p('geometry', 'bezier, straight, or elbow', shortKey: 'geo'),
    ],
  ),
  YoloitCliTool(
    command: 'link:color',
    alias: 'lcl',
    description: 'Set link color',
    group: 'link',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _p(
        'link_id',
        'Link id',
        required: true,
        aliases: const ['id'],
        shortKey: 'lid',
      ),
      _p('color', 'Color value', required: true, shortKey: 'cl'),
    ],
  ),
  YoloitCliTool(
    command: 'note',
    alias: 'nst',
    description: 'Set markdown note text',
    group: 'note',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('text', 'Markdown text', required: true, shortKey: 'tx'),
    ],
  ),
  YoloitCliTool(
    command: 'note:append',
    alias: 'nap',
    description: 'Append markdown note text',
    group: 'note',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('text', 'Markdown text', required: true, shortKey: 'tx'),
    ],
  ),
  YoloitCliTool(
    command: 'note:wrap',
    alias: 'nwr',
    description: 'Enable note auto-height wrapping',
    group: 'note',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'note:nowrap',
    alias: 'nnw',
    description: 'Disable note auto-height wrapping',
    group: 'note',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'checklist:add',
    alias: 'chad',
    description: 'Add checklist item',
    group: 'checklist',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'item',
        'Checklist item text',
        required: true,
        aliases: const ['text'],
        shortKey: 'it',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'checklist:check',
    alias: 'chck',
    description: 'Toggle checklist item state',
    group: 'checklist',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'item',
        'Item id or text',
        required: true,
        aliases: const ['id', 'text'],
        shortKey: 'it',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'checklist:uncheck',
    alias: 'chun',
    description: 'Toggle checklist item state',
    group: 'checklist',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'item',
        'Item id or text',
        required: true,
        aliases: const ['id', 'text'],
        shortKey: 'it',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:columns',
    alias: 'kcls',
    description: 'List kanban columns',
    group: 'kanban',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'kanban:add-column',
    alias: 'kadc',
    description: 'Add kanban column',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('name', 'Column name', required: true, shortKey: 'n'),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:rename-column',
    alias: 'krnc',
    description: 'Rename kanban column',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('column', 'Column id or name', required: true, shortKey: 'col'),
      _p('name', 'New column name', required: true, shortKey: 'n'),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:remove-column',
    alias: 'krmc',
    description: 'Remove kanban column',
    group: 'kanban',
    destructive: true,
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('column', 'Column id or name', required: true, shortKey: 'col'),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:add-card',
    alias: 'kadk',
    description:
        'Add kanban card. Parse "in/into/to <column>" as the required `column` and "named/called/titled <text>" as `title`.',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'column',
        'Target column name or id, for example Todo, Doing, Done',
        required: true,
        aliases: const <String>['column_name', 'lane', 'status', 'list'],
        shortKey: 'col',
      ),
      _p(
        'title',
        'Card title',
        required: true,
        aliases: const <String>['name', 'card_title'],
        shortKey: 't',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:move-card',
    alias: 'kmvk',
    description: 'Move kanban card',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
      _p(
        'to_column',
        'Destination column',
        required: true,
        aliases: const ['to'],
        shortKey: 'tc',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:remove-card',
    alias: 'krmk',
    description: 'Remove kanban card',
    group: 'kanban',
    destructive: true,
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:update-card',
    alias: 'kudk',
    description: 'Update kanban card title',
    group: 'kanban',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'card_id',
        'Card id',
        required: true,
        aliases: const ['cardId', 'id'],
        shortKey: 'cid',
      ),
      _p('title', 'New card title', required: true, shortKey: 't'),
    ],
  ),
  YoloitCliTool(
    command: 'kanban:cards',
    alias: 'kkls',
    description: 'List kanban cards',
    group: 'kanban',
    params: <YoloitCliToolParam>[_boardParam(), _panelParam()],
  ),
  YoloitCliTool(
    command: 'play',
    alias: 'play',
    description: 'Add media and start playback',
    group: 'playlist',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p(
        'file_or_url',
        'Media file path or URL',
        required: true,
        aliases: const ['path', 'url'],
        shortKey: 'u',
      ),
    ],
  ),
  YoloitCliTool(
    command: 'web:open',
    alias: 'wop',
    description: 'Open URL in webpage panel',
    group: 'webpage',
    params: <YoloitCliToolParam>[
      _boardParam(),
      _panelParam(),
      _p('url', 'URL to open', required: true, shortKey: 'u'),
    ],
  ),
];
