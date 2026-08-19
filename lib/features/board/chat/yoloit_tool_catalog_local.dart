import 'package:flutter/foundation.dart' show setEquals;
import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';

final RegExp _validFunctionNamePattern = RegExp(r'^[a-zA-Z0-9_]+$');

/// Local-model-specific extensions for [YoloitCliTool].
extension YoloitCliToolLocalTools on YoloitCliTool {
  /// Convert this tool definition into one or more [flm.LocalTool] schemas.
  List<flm.LocalTool> toLocalTools() {
    final allAliases = [alias, ...aliases].nonNulls.toList();
    final isCompact = allAliases.isNotEmpty;
    final properties = <String, Object?>{};
    final requiredKeys = <String>[];
    for (final param in params) {
      final propKey = isCompact ? param.compactKey : param.key;
      properties[propKey] = isCompact
          ? param.toCompactJsonSchema()
          : param.toJsonSchema();
      if (param.required) requiredKeys.add(propKey);
    }
    if (destructive) {
      final confirmKey = isCompact ? 'cf' : 'confirm';
      properties[confirmKey] = isCompact
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
    final desc = isCompact
        ? description
        : 'yoloit $command — $description.${destructive ? ' Ask for confirmation before using it.' : ''}';
    final metadata = <String, Object?>{
      'command': command,
      'group': group,
      'destructive': destructive,
    };
    final validFunctionName = _validFunctionNamePattern;
    var names = allAliases.isEmpty
        ? <String>[functionName]
        : allAliases.where((a) => validFunctionName.hasMatch(a)).toList();
    if (names.isEmpty) {
      names = <String>[functionName];
    }
    return <flm.LocalTool>[
      for (final name in names)
        flm.LocalTool.function(
          name: name,
          description: desc,
          parametersJsonSchema: schema,
          metadata: metadata,
        ),
    ];
  }
}

/// Catalog helpers that depend on `local_models_flutter` (VM-only).
class YoloitCliToolCatalogLocal {
  YoloitCliToolCatalogLocal._();

  /// All YoLoIT tools exported as [flm.LocalTool] schemas.
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
        for (final tool in YoloitCliToolCatalog.tools) ...tool.toLocalTools(),
      ]);

  /// Last (disabled set → result) memo so repeated calls with the same
  /// disabled configuration skip the per-tool conversion pass.
  static Set<String>? _lastDisabled;
  static List<flm.LocalTool>? _lastResult;

  /// Tools filtered by disabled function names.
  static List<flm.LocalTool> localToolsFor({
    Set<String> disabledFunctionNames = const <String>{},
  }) {
    if (disabledFunctionNames.isEmpty) return localTools;
    if (_lastResult != null &&
        setEquals(disabledFunctionNames, _lastDisabled)) {
      return _lastResult!;
    }
    final disabled = YoloitCliToolCatalog.normalizeFunctionNames(
      disabledFunctionNames,
    );
    final result = List<flm.LocalTool>.unmodifiable(<flm.LocalTool>[
      const flm.LocalTool.function(
        name: 'get_tools',
        description: 'List available YoLoIT CLI tools in compact JSON.',
        parametersJsonSchema: <String, Object?>{
          'type': 'object',
          'properties': <String, Object?>{},
          'additionalProperties': false,
        },
      ),
      for (final tool in YoloitCliToolCatalog.tools)
        if (tool.allFunctionNames.every((n) => !disabled.contains(n)))
          ...tool.toLocalTools(),
    ]);
    _lastDisabled = Set<String>.of(disabledFunctionNames);
    _lastResult = result;
    return result;
  }
}
