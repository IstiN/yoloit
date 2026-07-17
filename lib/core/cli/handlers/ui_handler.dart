import 'dart:convert';

import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_tree_normalizer.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';

/// CLI handler for declarative UI panels (`board.ui`).
class UiViewCliHandler extends PanelCliHandler {
  const UiViewCliHandler();

  @override
  String get typeId => UiViewPluginBase.kTypeId;

  @override
  List<String> get supportedActions =>
      const ['get', 'render', 'set-state', 'set-scripts'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) =>
      _panelPayload(panel);

  @override
  Map<String, CliActionHelp> get actionHelp => const {
    'get': CliActionHelp(
      description:
          'Read JSON tree, storage, resolved tree, text lines, and last event',
    ),
    'render': CliActionHelp(
      description: 'Replace the panel UI with a declarative JSON tree',
      params: {
        'tree': 'Root node object (type, children, …)',
        'json': 'Alias for tree when passing a JSON string',
      },
      example:
          'yoloit ui:render "<board>" "<panel>" \'{"type":"column","children":[{"type":"text","data":"Hi"}]}\'',
    ),
    'set-state': CliActionHelp(
      description:
          'Merge values into panel storage. Use {{key}} in tree text/button labels.',
      params: {
        'state': 'Object to merge into storage',
        'storage': 'Alias for state',
      },
    ),
    'set-scripts': CliActionHelp(
      description:
          'Merge onTap/onChange JavaScript handlers keyed by action id',
      params: {
        'scripts': 'Map of actionId → JS source',
      },
      example:
          'yoloit ui:set-scripts "<board>" "<panel>" \'{"bump":"yoloit.inc(\\"taps\\");"}\'',
    ),
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(ok: true, data: _panelPayload(panel));
      case 'render':
        final tree = parseUiTree(args['tree'] ?? args['json']);
        if (tree == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing or invalid "tree" (must be a JSON object)',
          );
        }
        return CliActionResult(
          ok: true,
          message: 'UI tree rendered',
          stateUpdate: {
            'tree': tree,
            '_storage': UiViewBindings.seedFieldsFromTree(
              tree,
              UiViewBindings.storageFromState(panel.state),
            ),
            '_lastEvent': null,
          },
        );
      case 'set-state':
        final patch = parseUiStatePatch(args['state'] ?? args['storage']);
        if (patch == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing or invalid "state" object',
          );
        }
        final current = UiViewBindings.storageFromState(panel.state);
        return CliActionResult(
          ok: true,
          message: 'UI storage updated',
          stateUpdate: {
            '_storage': <String, dynamic>{...current, ...patch},
          },
        );
      case 'set-scripts':
        final patch = parseUiScriptsPatch(args['scripts'] ?? args['_scripts']);
        if (patch == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing or invalid "scripts" object',
          );
        }
        final current = UiViewBindings.scriptsFromState(panel.state);
        return CliActionResult(
          ok: true,
          message: 'UI scripts updated',
          stateUpdate: {
            '_scripts': <String, dynamic>{...current, ...patch},
          },
        );
    }
    return CliActionResult(ok: false, message: 'Unknown action: $action');
  }

  Map<String, dynamic> _panelPayload(BoardPanelInstance panel) {
    final tree =
        UiViewPluginBase.treeFromState(panel.state) ??
        UiViewPluginBase.defaultTree();
    final storage = UiViewBindings.storageFromState(panel.state);
    final resolved = UiViewBindings.applyTree(tree, storage);
    return <String, dynamic>{
      'tree': tree,
      'resolvedTree': resolved,
      'storage': storage,
      'scripts': UiViewBindings.scriptsFromState(panel.state),
      'text': AppCliUtils.extractTextLines(resolved),
      if (panel.state['_lastEvent'] != null)
        'lastEvent': panel.state['_lastEvent'],
    };
  }
}

Map<String, dynamic>? parseUiStatePatch(Object? raw) {
  if (raw is Map) {
    return Map<String, dynamic>.from(raw.cast<String, dynamic>());
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded.cast<String, dynamic>());
      }
    } catch (_) {}
  }
  return null;
}

Map<String, String>? parseUiScriptsPatch(Object? raw) {
  if (raw is Map) {
    final out = <String, String>{};
    for (final entry in raw.entries) {
      final value = entry.value;
      if (value is String) {
        out['${entry.key}'] = value;
      }
    }
    return out.isEmpty ? null : out;
  }
  if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      return parseUiScriptsPatch(decoded);
    } catch (_) {}
  }
  return null;
}

/// Parses a declarative UI tree from CLI/LLM arguments.
Map<String, dynamic>? parseUiTree(Object? raw) {
  Map<String, dynamic>? tree;
  if (raw is Map) {
    tree = Map<String, dynamic>.from(raw);
  } else if (raw is String) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        tree = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
  }
  if (tree == null) return null;
  return UiViewTreeNormalizer.normalize(tree);
}
