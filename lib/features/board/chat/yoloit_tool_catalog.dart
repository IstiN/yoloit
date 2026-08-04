import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/cli/cli_text_argument_resolver.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

import 'package:yoloit/features/board/chat/cli_tools/app_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/auto_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/board_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/file_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/group_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/link_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/note_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/panel_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/run_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';
import 'package:yoloit/features/board/chat/cli_tools/ui_tools.dart';


class YoloitCliTool {
  const YoloitCliTool({
    required this.command,
    required this.description,
    this.alias,
    this.aliases = const <String>[],
    this.group = 'app',
    this.params = const <YoloitCliToolParam>[],
    this.destructive = false,
    this.humanVariants = const <String, List<String>>{},
  });

  final String command;
  final String description;
  final String? alias;
  final List<String> aliases;
  final String group;
  final List<YoloitCliToolParam> params;
  final bool destructive;

  /// Natural language phrases mapped by locale (e.g. 'ru', 'en').
  /// Used to generate training data for a tiny command-router model.
  /// Params are referenced as `{param_name}` placeholders.
  /// Example: `{'ru': ['создай заметку {title}'], 'en': ['create note {title}']}`
  final Map<String, List<String>> humanVariants;

  static final _validFunctionName = RegExp(r'^[a-zA-Z0-9_]+$');

  List<String> get _allAliases =>
      alias != null ? <String>[alias!, ...aliases] : aliases;

  String get functionName {
    if (_allAliases.isNotEmpty) {
      final validAlias = _allAliases.firstWhere(
        (a) => _validFunctionName.hasMatch(a),
        orElse: () => '',
      );
      if (validAlias.isNotEmpty) return validAlias;
    }
    return fullFunctionName;
  }

  String get fullFunctionName => YoloitCliToolCatalog.functionNameFor(command);
  List<String> get allFunctionNames => <String>{
      functionName,
      fullFunctionName,
      ..._allAliases,
    }.toList();

  /// Export for training catalog (help --format catalog).
  Map<String, Object?> toCatalogJson() {
    return {
      'command': command,
      'group': group,
      'description': description,
      'aliases': _allAliases,
      'destructive': destructive,
      'params':
          params
              .map(
                (p) => {
                  'name': p.key,
                  'required': p.required,
                  'description': p.description,
                },
              )
              .toList(),
      'human': humanVariants,
    };
  }


  /// OpenAI-compatible function definition for cloud providers.
  ///
  /// When [compact] is true (default), uses short tool aliases and param keys
  /// without per-field descriptions to reduce token usage.
  Map<String, Object?> toOpenAiFunctionDefinition({bool compact = true}) {
    final useCompact = compact;
    final properties = <String, Object?>{};
    final requiredKeys = <String>[];
    for (final param in params) {
      final propKey = useCompact ? param.compactKey : param.key;
      properties[propKey] =
          useCompact ? param.toCompactJsonSchema() : param.toJsonSchema();
      if (param.required) requiredKeys.add(propKey);
    }
    if (destructive) {
      final confirmKey = useCompact ? 'cf' : 'confirm';
      properties[confirmKey] =
          useCompact
              ? const <String, Object?>{'type': 'boolean'}
              : const <String, Object?>{
                'type': 'boolean',
                'description':
                    'Set true only after the user explicitly confirmed this destructive action.',
              };
      if (!useCompact) requiredKeys.add(confirmKey);
    }
    final schema = <String, Object?>{
      'type': 'object',
      'properties': properties,
      if (!useCompact) 'additionalProperties': false,
      if (requiredKeys.isNotEmpty) 'required': requiredKeys,
    };
    final name =
        useCompact && _allAliases.isNotEmpty ? functionName : fullFunctionName;
    final desc =
        useCompact
            ? description
            : 'yoloit $command — $description.${destructive ? ' Ask for confirmation before using it.' : ''}';
    return <String, Object?>{
      'type': 'function',
      'function': <String, Object?>{
        'name': name,
        'description': desc,
        'parameters': schema,
      },
    };
  }
}

class YoloitCliToolCatalog {
  YoloitCliToolCatalog._();

  static final List<YoloitCliTool> tools = List<YoloitCliTool>.unmodifiable(
    _tools,
  );


  static YoloitCliTool? byFunctionName(String name) {
    final resolvedName = _functionAliases[name] ?? name;
    if (name == 'get_tools' || name == 'list_tools') {
      return null;
    }
    final rawCommand =
        name.startsWith('yoloit ') ? name.substring('yoloit '.length) : name;
    final rawCommandWithColons = rawCommand.replaceAll('_', ':');
    final resolvedCommand =
        resolvedName.startsWith('yoloit ')
            ? resolvedName.substring('yoloit '.length)
            : resolvedName;
    final resolvedCommandWithColons = resolvedCommand.replaceAll('_', ':');
    for (final tool in _tools) {
      final names = <String>{
        tool.functionName,
        tool.fullFunctionName,
        ...tool._allAliases,
      };
      if (names.contains(resolvedName) ||
          names.contains(name) ||
          tool.command == rawCommand ||
          tool.command == rawCommandWithColons ||
          tool.command == resolvedCommand ||
          tool.command == resolvedCommandWithColons) {
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

  /// OpenAI function-calling payload for cloud LLM providers.
  static List<Map<String, Object?>> openAiToolDefinitions({
    Iterable<String> disabledFunctionNames = const <String>{},
    bool compact = true,
  }) {
    final disabled = normalizeFunctionNames(disabledFunctionNames);
    return <Map<String, Object?>>[
      for (final tool in _tools)
        if (!disabled.contains(tool.functionName) &&
            !disabled.contains(tool.fullFunctionName))
          tool.toOpenAiFunctionDefinition(compact: compact),
    ];
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

  /// Generate training catalog JSON for command-router model fine-tuning.
  /// Only includes commands that have humanVariants defined.
  /// Also merges any extra human variants loaded from YAML assets.
  /// Output format: { commands: [...], coverage: { total, withVariants, missing } }
  static String catalogJson([
    Map<String, Map<String, List<String>>>? yamlVariants,
  ]) {
    final withVariants = <Map<String, Object?>>[];
    final missing = <String>[];
    for (final tool in _tools) {
      final extras = yamlVariants?[tool.command] ?? {};
      final merged = <String, List<String>>{...tool.humanVariants};
      for (final entry in extras.entries) {
        merged.update(
          entry.key,
          (existing) => [...existing, ...entry.value],
          ifAbsent: () => entry.value,
        );
      }
      if (merged.isNotEmpty) {
        final json = tool.toCatalogJson();
        withVariants.add({...json, 'human': merged});
      } else {
        missing.add(tool.command);
      }
    }
    return jsonEncode({
      'commands': withVariants,
      'coverage': {
        'total': _tools.length,
        'withVariants': withVariants.length,
        'missing': missing,
      },
    });
  }

  /// Load human variants from bundled YAML assets asynchronously.
  /// Returns a map of command-id → {locale → [phrases]}.
  static Future<Map<String, Map<String, List<String>>>>
  loadYamlVariants() async {
    final result = <String, Map<String, List<String>>>{};
    const yamlFiles = [
      'assets/command_catalog/note.yaml',
      'assets/command_catalog/panel.yaml',
      'assets/command_catalog/board.yaml',
      'assets/command_catalog/app.yaml',
      'assets/command_catalog/checklist.yaml',
      'assets/command_catalog/kanban.yaml',
      'assets/command_catalog/misc.yaml',
    ];
    for (final assetPath in yamlFiles) {
      try {
        final raw = await rootBundle.loadString(assetPath);
        final doc = loadYaml(raw);
        _mergeYamlCommands(result, doc['commands'] as YamlList?);
      } catch (_) {
        // Skip missing/malformed YAML files
      }
    }
    return result;
  }

  /// Merges the `human` variants of each command in [commands] into
  /// [result], appending phrases per locale.
  static void _mergeYamlCommands(
    Map<String, Map<String, List<String>>> result,
    YamlList? commands,
  ) {
    if (commands == null) return;
    for (final cmd in commands) {
      final id = cmd['id'] as String?;
      if (id == null) continue;
      final locales = _parseHumanLocales(cmd['human']);
      if (locales.isEmpty) continue;
      result.putIfAbsent(id, () => {});
      for (final e in locales.entries) {
        result[id]!.update(
          e.key,
          (existing) => [...existing, ...e.value],
          ifAbsent: () => e.value,
        );
      }
    }
  }

  /// Parses a `human` YAML node into locale → phrases. A flat list without
  /// locale keys is stored under 'en'.
  static Map<String, List<String>> _parseHumanLocales(Object? human) {
    final locales = <String, List<String>>{};
    if (human is YamlMap) {
      for (final entry in human.entries) {
        final locale = entry.key as String;
        final phrases = entry.value;
        if (phrases is YamlList) {
          locales[locale] = phrases.whereType<String>().toList();
        }
      }
    } else if (human is YamlList) {
      // Flat list without locale — put under 'en'
      locales['en'] = human.whereType<String>().toList();
    }
    return locales;
  }
}

class YoloitCliToolArgumentNormalizer {
  YoloitCliToolArgumentNormalizer._();

  static String normalizeFunctionName({
    required String functionName,
    required String userMessage,
  }) {
    final text = userMessage.toLowerCase();
    return _redirectPanelFunctions(functionName, text) ??
        _redirectNoteFunctions(functionName, text) ??
        _redirectBoardFunctions(functionName, text) ??
        _redirectMiscFunctions(functionName, text) ??
        functionName;
  }

  static String? _redirectPanelFunctions(String functionName, String text) {
    return _redirectPanelHelp(functionName, text) ??
        _redirectPanelFocus(functionName, text) ??
        _redirectPanelShow(functionName, text);
  }

  static String? _redirectPanelHelp(String functionName, String text) {
    if (functionName == 'yoloit_panel_help' &&
        text.isNotEmpty &&
        (text.contains('details') || text.contains('content')) &&
        !text.contains('actions') &&
        !text.contains('available')) {
      return 'yoloit_panel';
    }
    return null;
  }

  static String? _redirectPanelFocus(String functionName, String text) {
    if (functionName == 'yoloit_board_focus' && text.contains('panel')) {
      return 'yoloit_panel_focus';
    }
    if (functionName == 'yoloit_panel' &&
        (text.contains('focus') || text.contains('фокус'))) {
      return 'yoloit_panel_focus';
    }
    return null;
  }

  static String? _redirectPanelShow(String functionName, String text) {
    if (functionName == 'yoloit_panel_focus' &&
        text.contains('show') &&
        text.contains('panel') &&
        !text.contains('focus')) {
      return 'yoloit_panel_show';
    }
    return null;
  }

  static String? _redirectNoteFunctions(String functionName, String text) {
    if (_isPanelCreateRequest(functionName, text)) {
      return 'yoloit_panel_create';
    }
    if (functionName == 'yoloit_note_replace') {
      return 'yoloit_note';
    }
    // Model picks "note" (set text) when user wants "note:create" (new panel).
    if (_isNoteCreateRequest(functionName, text)) {
      return 'ncrt';
    }
    return null;
  }

  static bool _isPanelCreateRequest(String functionName, String text) {
    if (functionName != 'yoloit_note_create') return false;
    return (text.contains('create') && text.contains('panel')) ||
        (text.contains('создай') && text.contains('панел')) ||
        (text.contains('сделай') && text.contains('панел'));
  }

  static bool _isNoteCreateRequest(String functionName, String text) {
    if (functionName != 'nst' &&
        functionName != 'yoloit_note' &&
        functionName != 'note') {
      return false;
    }
    return _mentionsNewNote(text);
  }

  static bool _mentionsNewNote(String text) {
    return text.contains('сделай заметку') ||
        text.contains('создай заметку') ||
        text.contains('новая заметка') ||
        text.contains('добавь заметку') ||
        (text.contains('create') && text.contains('note')) ||
        (text.contains('make') && text.contains('note')) ||
        (text.contains('new') && text.contains('note'));
  }

  static String? _redirectBoardFunctions(String functionName, String text) {
    final looksLikeBoardNavigation =
        text.contains('перейд') ||
        text.contains('переди') ||
        text.contains('переключ') ||
        text.contains('открой') ||
        text.contains('show') ||
        text.contains('open') ||
        text.contains('switch') ||
        text.contains('go to');
    final looksLikeContextOnly =
        text.contains('для следующих команд') ||
        text.contains('for subsequent commands') ||
        text.contains('as default context');
    if (functionName == 'yoloit_board_use' &&
        looksLikeBoardNavigation &&
        !looksLikeContextOnly) {
      return 'yoloit_board_focus';
    }
    return null;
  }

  static String? _redirectMiscFunctions(String functionName, String text) {
    if (functionName == 'yoloit_reload' && text.contains('restart')) {
      return 'yoloit_restart';
    }
    return null;
  }

  static Map<String, Object?> normalize({
    required String functionName,
    required Map<String, Object?> arguments,
    required String userMessage,
    ChatRuntimeContext? runtimeContext,
  }) {
    final normalized = Map<String, Object?>.from(arguments);
    // Strip LLM artifacts from string values (e.g. Mistral appends "/no_think").
    _stripLlmArtifacts(normalized);
    // Strip LLM placeholder values early so downstream logic sees them as missing.
    normalized.removeWhere((_, v) => _isMissing(v));
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    _canonicalizeCompactArguments(tool, normalized);
    // Strip chat/assistant panel IDs from tools that auto-resolve their own
    // panel type. The CLI finds the correct panel by type.
    _stripChatPanelForTypedTools(tool, normalized);
    _remapNoteCreateTitle(tool, normalized);
    _inferMissingPanelType(tool, normalized, userMessage);
    _normalizeUiArguments(tool?.command, normalized, userMessage);
    _normalizeHelpArguments(tool?.command, normalized, userMessage);
    _normalizeBoardArguments(tool?.command, normalized, userMessage);
    _normalizePanelArguments(tool?.command, normalized, userMessage);
    _normalizeLinkArguments(tool?.command, normalized, userMessage);
    _normalizeRuntimeContextArguments(
      tool?.command,
      normalized,
      userMessage,
      runtimeContext,
    );
    _applyConfirmationFlag(tool, normalized, userMessage);
    _applyRunInputEnterFlag(tool, normalized, userMessage);
    _applyRunAttachAnyFlag(tool, normalized, userMessage);
    CliTextArgumentResolver.resolveInArguments(normalized);
    _encodeStructuredJsonArguments(normalized);
    return normalized;
  }

  /// When note→note:create redirect happened, remap text→title.
  static void _remapNoteCreateTitle(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
  ) {
    if (tool?.command == 'note:create' &&
        _isMissing(normalized['title']) &&
        _isMissing(normalized['ti'])) {
      final text = normalized.remove('text') ?? normalized.remove('tx');
      if (text != null) {
        normalized['title'] = text;
      }
    }
  }

  static void _inferMissingPanelType(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (tool?.command == 'panel:create' && _isMissing(normalized['type'])) {
      final type = _inferPanelType(userMessage);
      if (type != null) {
        normalized['type'] = type;
      }
    }
  }

  static void _applyConfirmationFlag(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (tool?.destructive == true &&
        _isMissing(normalized['confirm']) &&
        _mentionsConfirmation(userMessage)) {
      normalized['confirm'] = true;
    }
  }

  static void _applyRunInputEnterFlag(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (tool?.command == 'run:input' &&
        _isMissing(normalized['enter']) &&
        userMessage.toLowerCase().contains('enter')) {
      normalized['enter'] = true;
    }
  }

  static void _applyRunAttachAnyFlag(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (tool?.command == 'run:attach' &&
        _isMissing(normalized['any']) &&
        (userMessage.toLowerCase().contains('allow stopped') ||
            userMessage.toLowerCase().contains('allowing stopped'))) {
      normalized['any'] = true;
    }
  }

  static void _canonicalizeCompactArguments(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
  ) {
    if (tool == null) return;
    for (final param in tool.params) {
      if (_isMissing(normalized[param.key])) {
        for (final key in param.lookupKeys) {
          if (key != param.key && !_isMissing(normalized[key])) {
            normalized[param.key] = normalized[key];
            break;
          }
        }
      }
    }
  }

  /// For note/checklist/kanban tools, strip chat/assistant panel IDs from the
  /// arguments. The model sometimes passes the assistant panel ID from the
  /// system prompt context snapshot, but the CLI auto-resolves the correct
  /// panel by type.
  static void _stripChatPanelForTypedTools(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
  ) {
    if (tool == null) return;
    final g = tool.group;
    if (g != 'note' &&
        g != 'checklist' &&
        g != 'kanban' &&
        g != 'playlist' &&
        g != 'ui') {
      return;
    }
    for (final key in const [
      'panel',
      'panel_id',
      'panel_title',
      'p',
      'id',
      'board',
      'board_id',
      'board_name',
      'b',
    ]) {
      final v = normalized[key];
      if (v is String && _isChatPanelId(v)) {
        normalized.remove(key);
      }
    }
  }

  static bool _isChatPanelId(String id) {
    final lower = id.toLowerCase();
    return lower.contains('assistant') ||
        lower.contains('yolo_badge') ||
        lower.contains('yolochat');
  }

  static void _normalizeUiArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command != 'ui:render' && command != 'do') return;
    final tree = normalized['tree'] ?? normalized['j'] ?? normalized['json'];
    if (tree is Map) {
      final map = Map<String, dynamic>.from(tree);
      if (command == 'ui:render' &&
          map.containsKey('tree') &&
          !map.containsKey('type')) {
        normalized['tree'] = map['tree'];
        return;
      }
      if (command == 'do' &&
          normalized['action'] == 'render' &&
          map.containsKey('tree')) {
        normalized['json'] = jsonEncode(map);
      }
    }
  }

  static void _encodeStructuredJsonArguments(Map<String, Object?> normalized) {
    const jsonKeys = <String>{'json', 'j', 'tree'};
    for (final key in jsonKeys) {
      final value = normalized[key];
      if (value is Map || value is List) {
        normalized[key] = jsonEncode(value);
        continue;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.startsWith('```')) {
          normalized[key] = _stripMarkdownFence(trimmed);
        }
      }
    }
  }

  static String? _inferUiPanelTitle(String userMessage) {
    final text = userMessage.toLowerCase();
    if (text.contains('мой список') || text.contains('my list')) {
      return 'Мой список';
    }
    if (text.contains('пример') && RegExp(r'списк').hasMatch(text)) {
      return 'Пример списка';
    }
    if (RegExp(r'списк|checklist item').hasMatch(text) ||
        RegExp(r'\blists?\b').hasMatch(text)) {
      return 'Список';
    }
    if (text.contains('карточк') || text.contains('card')) return 'Карточка';
    if (text.contains('dashboard') || text.contains('дашборд')) {
      return 'Dashboard';
    }
    if (text.contains('кастомн') && text.contains('ui')) return 'UI View';
    if (text.contains('custom ui')) return 'UI View';
    return null;
  }

  static void _normalizeHelpArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command != 'help' || !_isMissing(normalized['format'])) {
      return;
    }
    final text = userMessage.toLowerCase();
    if (text.contains('detailed') || text.contains('detail')) {
      normalized['format'] = 'detailed';
      return;
    }
    if (text.contains('short')) {
      normalized['format'] = 'short';
      return;
    }
    if (text.contains('catalog')) {
      normalized['format'] = 'catalog';
      return;
    }
    if (text.contains('tools')) {
      normalized['format'] = 'tools';
      return;
    }
    if (text.contains('mermaid')) {
      normalized['format'] = 'mermaid';
    }
  }

  static void _normalizeBoardArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    _normalizeBoardZoomArguments(command, normalized, userMessage);
    _normalizeBoardArrangeArguments(command, normalized, userMessage);
    _normalizeBoardTranslateArguments(command, normalized, userMessage);
    _normalizeBoardTargetArguments(command, normalized, userMessage);
  }

  /// Fills [key] with the first number found after [label] in the user
  /// message, unless the argument is already present.
  static void _fillNumberFromLabel(
    Map<String, Object?> normalized,
    String userMessage,
    String key,
    RegExp label,
  ) {
    if (!_isMissing(normalized[key])) return;
    final value = _numberAfterLabel(userMessage, label);
    if (value != null) normalized[key] = value;
  }

  static void _normalizeBoardZoomArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command == 'board:zoom' && _isMissing(normalized['scale'])) {
      final scale = _firstNumberAfter(userMessage, RegExp(r'\bzoom\b|\bto\b'));
      if (scale != null) normalized['scale'] = scale;
    }
  }

  static void _normalizeBoardArrangeArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command != 'board:arrange') return;
    final text = userMessage.toLowerCase();
    if (_isMissing(normalized['direction'])) {
      if (text.contains('right')) {
        normalized['direction'] = 'right';
      } else if (text.contains('down')) {
        normalized['direction'] = 'down';
      }
    }
    _fillNumberFromLabel(
      normalized,
      userMessage,
      'h_spacing',
      RegExp(r'horizontal spacing|h spacing'),
    );
    _fillNumberFromLabel(
      normalized,
      userMessage,
      'v_spacing',
      RegExp(r'vertical spacing|v spacing'),
    );
  }

  static void _normalizeBoardTranslateArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command != 'board:translate') return;
    _fillNumberFromLabel(normalized, userMessage, 'x', RegExp(r'\bx\b'));
    _fillNumberFromLabel(normalized, userMessage, 'y', RegExp(r'\by\b'));
  }

  static void _normalizeBoardTargetArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if ((command == 'board:delete' ||
            command == 'board:archive' ||
            command == 'board:unarchive') &&
        _isMissing(normalized['id_or_name'])) {
      final boardName = _extractNamedTarget(
        userMessage,
        RegExp(r'(delete|archive|unarchive) board'),
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
      _fillNumberFromLabel(normalized, userMessage, 'x', RegExp(r'\bx\b'));
      _fillNumberFromLabel(normalized, userMessage, 'y', RegExp(r'\by\b'));
    }
    if (command == 'panel:resize') {
      _normalizePanelResizeArguments(normalized, userMessage);
    }
    _normalizePanelTitleArguments(command, normalized, userMessage);
    _normalizePanelTargetArguments(command, normalized, userMessage);
  }

  static void _normalizePanelResizeArguments(
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    _applyResizeDimensions(normalized, _extractResizePreset(userMessage));
    _applyResizeDimensions(normalized, _extractSizePair(userMessage));
    _fillNumberFromLabel(
      normalized,
      userMessage,
      'width',
      RegExp(r'\bwidth\b|ширин|широк', caseSensitive: false),
    );
    _fillNumberFromLabel(
      normalized,
      userMessage,
      'height',
      RegExp(r'\bheight\b|высот', caseSensitive: false),
    );
    _applyResizeIntentDefault(normalized, userMessage);
  }

  static void _applyResizeDimensions(
    Map<String, Object?> normalized,
    (num, num)? dimensions,
  ) {
    if (dimensions == null) return;
    if (_isMissing(normalized['width'])) normalized['width'] = dimensions.$1;
    if (_isMissing(normalized['height'])) normalized['height'] = dimensions.$2;
  }

  static void _applyResizeIntentDefault(
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if ((_isMissing(normalized['width']) ||
            _isMissing(normalized['height'])) &&
        _mentionsResizeIntent(userMessage)) {
      normalized['width'] =
          _isMissing(normalized['width']) ? 500 : normalized['width'];
      normalized['height'] =
          _isMissing(normalized['height']) ? 400 : normalized['height'];
    }
  }

  static void _normalizePanelTitleArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command == 'panel:create' && _isMissing(normalized['title'])) {
      final title = _extractTitle(userMessage);
      if (title != null) normalized['title'] = title;
    }
    if (command == 'ui:create' && _isMissing(normalized['title'])) {
      final title = _extractTitle(userMessage) ?? _inferUiPanelTitle(userMessage);
      if (title != null) normalized['title'] = title;
    }
    if (command == 'ui:render' || command == 'ui:get' || command == 'ui:edit') {
      if (_isMissing(normalized['panel'])) {
        final panel =
            _extractTitle(userMessage) ?? _inferUiPanelTitle(userMessage);
        if (panel != null) normalized['panel'] = panel;
      }
    }
  }

  static void _normalizePanelTargetArguments(
    String? command,
    Map<String, Object?> normalized,
    String userMessage,
  ) {
    if (command != null &&
        (command == 'panel' || command.startsWith('panel:')) &&
        _isMissing(normalized['panel']) &&
        !_isMissing(normalized['id_or_name'])) {
      normalized['panel'] = normalized['id_or_name'];
      normalized.remove('id_or_name');
    }
    if (command == 'panel:focus' || command == 'panel:show') {
      _fillNamedPanelTarget(
        normalized,
        userMessage,
        RegExp(r'panel named|panel called|panel titled'),
      );
    }
    if (command == 'panel:delete') {
      _fillNamedPanelTarget(normalized, userMessage, RegExp(r'delete panel'));
    }
  }

  /// Fills the `panel` argument with the name captured after [phrase] in the
  /// user message, unless the argument is already present.
  static void _fillNamedPanelTarget(
    Map<String, Object?> normalized,
    String userMessage,
    RegExp phrase,
  ) {
    if (!_isMissing(normalized['panel'])) return;
    final panelName = _extractNamedTarget(userMessage, phrase);
    if (panelName != null) normalized['panel'] = panelName;
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
    _applyContextBoardId(command, normalized, userMessage, runtimeContext);
    if (!_usesPanelArgument(command)) return;
    final panelId = runtimeContext.panelId?.trim();
    if (panelId == null || panelId.isEmpty) return;
    _applyContextPanelId(normalized, userMessage, runtimeContext, panelId);
    _applyNoteLookupPanelOverride(
      command,
      normalized,
      userMessage,
      runtimeContext,
      panelId,
    );
  }

  static void _applyContextBoardId(
    String command,
    Map<String, Object?> normalized,
    String userMessage,
    ChatRuntimeContext runtimeContext,
  ) {
    if (!_usesBoardArgument(command)) return;
    final boardId = runtimeContext.boardId?.trim();
    if (boardId != null &&
        boardId.isNotEmpty &&
        (_mentionsCurrentBoard(userMessage) ||
            _looselySameIdentifier(
              normalized['id_or_name'],
              'current board',
            ) ||
            _looselySameIdentifier(normalized['board'], 'current board'))) {
      normalized['id_or_name'] = boardId;
    }
  }

  static void _applyContextPanelId(
    Map<String, Object?> normalized,
    String userMessage,
    ChatRuntimeContext runtimeContext,
    String panelId,
  ) {
    final panelValue = normalized['panel'];
    if (_mentionsCurrentPanel(userMessage) ||
        _looselySameIdentifier(panelValue, panelId) ||
        _looselySameIdentifier(panelValue, runtimeContext.panelTitle)) {
      normalized['panel'] = panelId;
    }
  }

  static void _applyNoteLookupPanelOverride(
    String command,
    Map<String, Object?> normalized,
    String userMessage,
    ChatRuntimeContext runtimeContext,
    String panelId,
  ) {
    if ((command != 'panel' && command != 'panel:focus') ||
        !_mentionsNoteLookupIntent(userMessage)) {
      return;
    }
    final currentPanelValue = '${normalized['panel'] ?? ''}'.trim();
    final query = _inferNoteLookupPanelQuery(userMessage);
    if (query != null &&
        query.isNotEmpty &&
        _looksLikeOpaquePanelId(currentPanelValue)) {
      normalized['panel'] = query;
      return;
    }
    final targetsCurrentChatPanel =
        currentPanelValue.isEmpty ||
        _looselySameIdentifier(currentPanelValue, panelId) ||
        _looselySameIdentifier(
          currentPanelValue,
          runtimeContext.panelTitle,
        ) ||
        _isChatPanelId(currentPanelValue);
    if (targetsCurrentChatPanel) {
      if (query != null && query.isNotEmpty) {
        normalized['panel'] = query;
      } else {
        normalized.remove('panel');
      }
    }
  }

  static const Set<String> _panelArgumentCommands = <String>{
    'panel',
    'do',
    'note',
    'play',
    'pause',
    'stop',
    'next',
    'prev',
    'playlist:list',
    'web:open',
  };

  static const List<String> _panelArgumentPrefixes = <String>[
    'panel:',
    'ui:',
    'note:',
    'checklist:',
    'kanban:',
    'run:',
  ];

  static bool _usesPanelArgument(String command) {
    if (_panelArgumentCommands.contains(command)) return true;
    for (final prefix in _panelArgumentPrefixes) {
      if (command.startsWith(prefix)) return true;
    }
    return false;
  }

  static bool _usesBoardArgument(String command) {
    return command == 'board' || command.startsWith('board:');
  }

  /// Ordered panel-type inference rules. Each rule is a list of alternatives
  /// (OR); an alternative is a list of substrings that must all be contained
  /// in the lowercased user message (AND). The first matching rule wins.
  static const List<(List<List<String>>, String)> _panelTypeRules =
      <(List<List<String>>, String)>[
        (
          <List<String>>[
            <String>['kanban'],
          ],
          'board.kanban',
        ),
        (
          <List<String>>[
            <String>['run panel'],
            <String>['dev server'],
            <String>['terminal'],
            <String>['console'],
          ],
          'board.run',
        ),
        (
          <List<String>>[
            <String>['markdown'],
            <String>['note'],
            <String>['замет'],
          ],
          'board.note.markdown',
        ),
        (
          <List<String>>[
            <String>['канбан'],
          ],
          'board.kanban',
        ),
        (
          <List<String>>[
            <String>['терминал'],
            <String>['консол'],
          ],
          'board.run',
        ),
        (
          <List<String>>[
            <String>['чеклист'],
          ],
          'board.checklist',
        ),
        (
          <List<String>>[
            <String>['чат'],
          ],
          'board.chat',
        ),
        (
          <List<String>>[
            <String>['checklist'],
          ],
          'board.checklist',
        ),
        (
          <List<String>>[
            <String>['webpage'],
            <String>['web panel'],
          ],
          'board.webpage',
        ),
        (
          <List<String>>[
            <String>['playlist'],
            <String>['media'],
          ],
          'board.playlist',
        ),
        (
          <List<String>>[
            <String>['кастомн', 'ui'],
          ],
          'board.ui',
        ),
        (
          <List<String>>[
            <String>['кастом', 'ui'],
            <String>['кастом', 'view'],
          ],
          'board.ui',
        ),
        (
          <List<String>>[
            <String>['custom ui'],
            <String>['ui view'],
            <String>['json ui'],
            <String>['декларатив'],
          ],
          'board.ui',
        ),
        (
          <List<String>>[
            <String>['ui', 'список'],
            <String>['ui', 'карточ'],
            <String>['ui', 'панел'],
            <String>['json', 'список'],
            <String>['json', 'карточ'],
            <String>['json', 'панел'],
          ],
          'board.ui',
        ),
        (
          <List<String>>[
            <String>['chat panel'],
          ],
          'board.chat',
        ),
      ];

  static String? _inferPanelType(String userMessage) {
    final text = userMessage.toLowerCase();
    for (final (alternatives, type) in _panelTypeRules) {
      if (_matchesPanelTypeRule(text, alternatives)) return type;
    }
    return null;
  }

  static bool _matchesPanelTypeRule(
    String text,
    List<List<String>> alternatives,
  ) {
    for (final alternative in alternatives) {
      if (alternative.every(text.contains)) return true;
    }
    return false;
  }

  /// Strip known LLM artifacts from string values (e.g. Mistral's "/no_think").
  static void _stripLlmArtifacts(Map<String, Object?> args) {
    for (final key in args.keys.toList()) {
      final v = args[key];
      if (v is String) {
        args[key] =
            v
                .replaceAll(RegExp(r'\s*/no_think\s*'), '')
                .replaceAll(RegExp(r'\s*/think\s*'), '')
                .trim();
      }
    }
  }

  static String _stripMarkdownFence(String value) {
    var text = value.trim();
    if (!text.startsWith('```')) return text;
    text = text.replaceFirst(RegExp(r'^```[a-zA-Z]*\s*'), '');
    text = text.replaceFirst(RegExp(r'\s*```$'), '');
    return text.trim();
  }

  static bool _isMissing(Object? value) {
    if (value == null) return true;
    if (value is String) {
      final v = value.trim();
      if (v.isEmpty) return true;
      // Treat common LLM placeholder tokens as missing.
      if (v == '__' || v == '_' || v == '...' || v == 'null' || v == 'none') {
        return true;
      }
    }
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

  static (num, num)? _extractSizePair(String source) {
    final match = RegExp(r'(\d{2,4})\s*[xх×]\s*(\d{2,4})').firstMatch(source);
    if (match == null) return null;
    final width = int.tryParse(match.group(1) ?? '');
    final height = int.tryParse(match.group(2) ?? '');
    if (width == null || height == null) return null;
    return (width, height);
  }

  static bool _mentionsResizeIntent(String userMessage) {
    final text = userMessage.toLowerCase();
    return text.contains('resize') ||
        text.contains('bigger') ||
        text.contains('larger') ||
        text.contains('увелич') ||
        text.contains('больше');
  }

  static (num, num)? _extractResizePreset(String userMessage) {
    final text = userMessage.toLowerCase();
    if (RegExp(r'\bsmall\b|\bsm\b|маленьк').hasMatch(text)) return (420, 300);
    if (RegExp(r'\bmedium\b|\bmd\b|средн').hasMatch(text)) return (720, 480);
    if (RegExp(r'\bdesktop\b|\bdesk\b|десктоп').hasMatch(text)) {
      return (1200, 800);
    }
    if (RegExp(r'\blarge\b|\blg\b|\bxl\b|больш').hasMatch(text)) {
      return (1400, 900);
    }
    if (RegExp(r'\bmobile\b|\bphone\b|мобил').hasMatch(text)) {
      return (390, 844);
    }
    if (RegExp(r'\btablet\b|\btab\b|планшет').hasMatch(text)) {
      return (768, 1024);
    }
    return null;
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

  static bool _mentionsNoteLookupIntent(String userMessage) {
    final text = userMessage.toLowerCase();
    final asksToShowOrFocus =
        text.contains('show') ||
        text.contains('open') ||
        text.contains('focus') ||
        text.contains('покажи') ||
        text.contains('открой') ||
        text.contains('фокус');
    final mentionsNote =
        text.contains('note') ||
        text.contains('замет') ||
        text.contains('mermaid') ||
        text.contains('diagram') ||
        text.contains('диаграм');
    return asksToShowOrFocus && mentionsNote;
  }

  static String? _inferNoteLookupPanelQuery(String userMessage) {
    final lower = userMessage.toLowerCase();
    if (lower.contains('mermaid')) return 'mermaid';
    if (lower.contains('диаграм')) return 'диаграмма';
    return null;
  }

  static bool _looksLikeOpaquePanelId(String value) =>
      RegExp(r'^p-\d+$').hasMatch(value.trim());

  static bool _mentionsCurrentBoard(String userMessage) {
    final text = userMessage.toLowerCase();
    return text.contains('current board') ||
        (text.contains('this') && text.contains('board')) ||
        text.contains('this board');
  }

  static bool _looselySameIdentifier(Object? first, String? second) {
    if (first == null || second == null) return false;
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    return normalize('$first') == normalize(second);
  }
}

// Compact alias system: 67 tools with short aliases + shortKey params reduce
// local LLM tool schema token count by ~60-70% compared to verbose format.
final List<YoloitCliTool> _tools = <YoloitCliTool>[
  ...autoTools,
  ...appTools,
  ...boardTools,
  ...panelTools,
  ...uiTools,
  ...groupTools,
  ...runTools,
  ...noteTools,
  ...fileTools,
  ...linkTools,
];

