import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';

import 'package:yoloit/features/board/chat/cli_tools/app_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/board_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/file_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/link_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/note_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/panel_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/run_tools.dart';
import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';


class YoloitCliTool {
  const YoloitCliTool({
    required this.command,
    required this.description,
    this.alias,
    this.group = 'app',
    this.params = const <YoloitCliToolParam>[],
    this.destructive = false,
    this.humanVariants = const <String, List<String>>{},
  });

  final String command;
  final String description;
  final String? alias;
  final String group;
  final List<YoloitCliToolParam> params;
  final bool destructive;

  /// Natural language phrases mapped by locale (e.g. 'ru', 'en').
  /// Used to generate training data for a tiny command-router model.
  /// Params are referenced as `{param_name}` placeholders.
  /// Example: `{'ru': ['создай заметку {title}'], 'en': ['create note {title}']}`
  final Map<String, List<String>> humanVariants;

  String get functionName =>
      alias ?? YoloitCliToolCatalog.functionNameFor(command);
  String get fullFunctionName => YoloitCliToolCatalog.functionNameFor(command);

  /// Export for training catalog (help --format catalog).
  Map<String, Object?> toCatalogJson() {
    return {
      'command': command,
      'group': group,
      'description': description,
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
    final rawCommand =
        name.startsWith('yoloit ') ? name.substring('yoloit '.length) : name;
    final rawCommandWithColons = rawCommand.replaceAll('_', ':');
    final resolvedCommand =
        resolvedName.startsWith('yoloit ')
            ? resolvedName.substring('yoloit '.length)
            : resolvedName;
    final resolvedCommandWithColons = resolvedCommand.replaceAll('_', ':');
    for (final tool in _tools) {
      if (tool.functionName == resolvedName ||
          tool.functionName == name ||
          tool.fullFunctionName == resolvedName ||
          tool.alias == name ||
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
        final commands = doc['commands'] as YamlList?;
        if (commands == null) continue;
        for (final cmd in commands) {
          final id = cmd['id'] as String?;
          if (id == null) continue;
          final human = cmd['human'];
          if (human == null) continue;
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
          if (locales.isNotEmpty) {
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
      } catch (_) {
        // Skip missing/malformed YAML files
      }
    }
    return result;
  }
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
            (text.contains('создай') && text.contains('панел')) ||
            (text.contains('сделай') && text.contains('панел')))) {
      return 'yoloit_panel_create';
    }
    if (functionName == 'yoloit_board_focus' && text.contains('panel')) {
      return 'yoloit_panel_focus';
    }
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
    if (functionName == 'yoloit_panel' &&
        (text.contains('focus') || text.contains('фокус'))) {
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
    // Model picks "note" (set text) when user wants "note:create" (new panel).
    if ((functionName == 'nst' ||
            functionName == 'yoloit_note' ||
            functionName == 'note') &&
        (text.contains('сделай заметку') ||
            text.contains('создай заметку') ||
            text.contains('новая заметка') ||
            text.contains('добавь заметку') ||
            (text.contains('create') && text.contains('note')) ||
            (text.contains('make') && text.contains('note')) ||
            (text.contains('new') && text.contains('note')))) {
      return 'ncrt';
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
    // Strip LLM artifacts from string values (e.g. Mistral appends "/no_think").
    _stripLlmArtifacts(normalized);
    // Strip LLM placeholder values early so downstream logic sees them as missing.
    normalized.removeWhere((_, v) => _isMissing(v));
    final tool = YoloitCliToolCatalog.byFunctionName(functionName);
    _canonicalizeCompactArguments(tool, normalized);
    // Strip chat/assistant panel IDs from tools that auto-resolve their own
    // panel type. The CLI finds the correct panel by type.
    _stripChatPanelForTypedTools(tool, normalized);
    // When note→note:create redirect happened, remap text→title.
    if (tool?.command == 'note:create' &&
        _isMissing(normalized['title']) &&
        _isMissing(normalized['ti'])) {
      final text = normalized.remove('text') ?? normalized.remove('tx');
      if (text != null) {
        normalized['title'] = text;
      }
    }
    if (tool?.command == 'panel:create' && _isMissing(normalized['type'])) {
      final type = _inferPanelType(userMessage);
      if (type != null) {
        normalized['type'] = type;
      }
    }
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

  static void _canonicalizeCompactArguments(
    YoloitCliTool? tool,
    Map<String, Object?> normalized,
  ) {
    if (tool == null) return;
    for (final param in tool.params) {
      if (_isMissing(normalized[param.key])) {
        final shortKey = param.shortKey;
        if (shortKey != null && !_isMissing(normalized[shortKey])) {
          normalized[param.key] = normalized[shortKey];
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
    if (g != 'note' && g != 'checklist' && g != 'kanban' && g != 'playlist') {
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
      final preset = _extractResizePreset(userMessage);
      if (preset != null) {
        if (_isMissing(normalized['width'])) normalized['width'] = preset.$1;
        if (_isMissing(normalized['height'])) normalized['height'] = preset.$2;
      }
      final sizePair = _extractSizePair(userMessage);
      if (sizePair != null) {
        if (_isMissing(normalized['width'])) normalized['width'] = sizePair.$1;
        if (_isMissing(normalized['height'])) {
          normalized['height'] = sizePair.$2;
        }
      }
      if (_isMissing(normalized['width'])) {
        final value = _numberAfterLabel(
          userMessage,
          RegExp(r'\bwidth\b|ширин|широк', caseSensitive: false),
        );
        if (value != null) normalized['width'] = value;
      }
      if (_isMissing(normalized['height'])) {
        final value = _numberAfterLabel(
          userMessage,
          RegExp(r'\bheight\b|высот', caseSensitive: false),
        );
        if (value != null) normalized['height'] = value;
      }
      if ((_isMissing(normalized['width']) ||
              _isMissing(normalized['height'])) &&
          _mentionsResizeIntent(userMessage)) {
        normalized['width'] =
            _isMissing(normalized['width']) ? 500 : normalized['width'];
        normalized['height'] =
            _isMissing(normalized['height']) ? 400 : normalized['height'];
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
    if (_usesBoardArgument(command)) {
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
    if (!_usesPanelArgument(command)) return;
    final panelId = runtimeContext.panelId?.trim();
    if (panelId == null || panelId.isEmpty) return;
    final panelValue = normalized['panel'];
    if (_mentionsCurrentPanel(userMessage) ||
        _looselySameIdentifier(panelValue, panelId) ||
        _looselySameIdentifier(panelValue, runtimeContext.panelTitle)) {
      normalized['panel'] = panelId;
    }
    if ((command == 'panel' || command == 'panel:focus') &&
        _mentionsNoteLookupIntent(userMessage)) {
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
        command == 'pause' ||
        command == 'stop' ||
        command == 'next' ||
        command == 'prev' ||
        command == 'playlist:list' ||
        command == 'web:open';
  }

  static bool _usesBoardArgument(String command) {
    return command == 'board' || command.startsWith('board:');
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
      final value = _argumentValue(param, arguments, runtimeContext, tool);
      if (_isMissing(value)) {
        if (param.required &&
            !(_cliAutoResolvesPanel(tool.group) &&
                param.runtimeDefault == YoloitCliRuntimeDefault.panel)) {
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
    YoloitCliTool tool,
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
      YoloitCliRuntimeDefault.panel => _panelDefault(runtimeContext, tool),
      null => null,
    };
  }

  /// Returns the runtime panel default, but skips chat/assistant panels for
  /// tools that operate on typed panels (note, checklist, kanban). The CLI
  /// auto-resolves the correct panel by type when none is provided.
  Object? _panelDefault(ChatRuntimeContext? ctx, YoloitCliTool tool) {
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
        group == 'playlist';
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

    // Check the well-known install path first (~/.config/yoloit/yoloit).
    // CliServer._installCliScript() always writes the script here, so this
    // works for production app bundles where no source tree is present.
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final installed = File(p.join(home, '.config', 'yoloit', 'yoloit'));
      if (installed.existsSync()) return installed.path;
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


// Compact alias system: 67 tools with short aliases + shortKey params reduce
// local LLM tool schema token count by ~60-70% compared to verbose format.
final List<YoloitCliTool> _tools = <YoloitCliTool>[
  ...appTools,
  ...boardTools,
  ...panelTools,
  ...runTools,
  ...noteTools,
  ...fileTools,
  ...linkTools,
];
