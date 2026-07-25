import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_actions.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_script_runner.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';
import 'package:yoloit/features/board/widgets/js_widget_cube_3d_host.dart';
import 'package:yoloit/features/board/widgets/js_widget_image_resolver.dart';
import 'package:yoloit/features/board/widgets/js_widget_media_kit_host.dart';

/// Declarative JSON UI panel — renders a widget tree without a JS app runtime.
class UiViewPlugin extends UiViewPluginBase {
  const UiViewPlugin();

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    final rawTree =
        UiViewPluginBase.treeFromState(panel.state) ??
        UiViewPluginBase.defaultTree();
    final storage = UiViewBindings.storageFromState(panel.state);
    final tree = UiViewBindings.applyTree(rawTree, storage);
    final fieldRegistry = UiViewFieldRegistry();
    final renderer = JsonWidgetRenderer(
      fieldRegistry: fieldRegistry,
      mediaHost: createYoloitMediaHost(),
      js3dHost: createYoloitCube3dHost(),
      imageResolver: createExternalImageResolver(panel.state),
      onEvent: (actionId, payload) {
        if (actionId == '_field') {
          final key = payload['key'] as String?;
          if (key != null && key.isNotEmpty) {
            renderContext.onUpdateState(
              UiViewBindings.applyFieldStorage(
                state: panel.state,
                key: key,
                value: payload['value'],
              ),
            );
          }
          return;
        }
        final stateWithFields = UiViewBindings.withLiveFields(
          panel.state,
          fieldRegistry,
        );
        renderContext.onUpdateState(
          UiViewBindings.applyTap(
            state: stateWithFields,
            actionId: actionId,
            payload: payload,
            runScript: UiViewScriptRunner.instance.runAction,
          ),
        );
      },
    );
    return ClipRect(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (storage['_toast'] != null)
            Material(
              color: accentColor.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${storage['_toast']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onPressed: () {
                        final next = Map<String, dynamic>.from(storage)
                          ..remove('_toast');
                        renderContext.onUpdateState(<String, dynamic>{
                          ...panel.state,
                          '_storage': next,
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),
          renderer.build(tree, context),
        ],
      ),
    );
  }

  @override
  Widget buildEditorDialog(BuildContext context, BoardPanelInstance panel) =>
      _UiViewEditorDialog(panel: panel);
}

class _UiViewEditorDialog extends StatefulWidget {
  const _UiViewEditorDialog({required this.panel});

  final BoardPanelInstance panel;

  @override
  State<_UiViewEditorDialog> createState() => _UiViewEditorDialogState();
}

enum _UiEditorMode { json, preview, scripts }

class _UiViewEditorDialogState extends State<_UiViewEditorDialog> {
  late final TextEditingController _controller;
  late final TextEditingController _scriptController;
  late final JsonWidgetRenderer _previewRenderer;
  late final UiViewFieldRegistry _previewFieldRegistry;
  late Map<String, dynamic> _previewStorage;
  late Map<String, String> _scripts;
  String? _parseError;
  _UiEditorMode _mode = _UiEditorMode.preview;
  String? _selectedActionId;

  @override
  void initState() {
    super.initState();
    final tree =
        UiViewPluginBase.treeFromState(widget.panel.state) ??
        UiViewPluginBase.defaultTree();
    _previewStorage = UiViewBindings.storageFromState(widget.panel.state);
    _scripts = UiViewBindings.scriptsFromState(widget.panel.state);
    _controller = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(tree),
    );
    _scriptController = TextEditingController();
    _previewFieldRegistry = UiViewFieldRegistry();
    _previewRenderer = JsonWidgetRenderer(
      fieldRegistry: _previewFieldRegistry,
      mediaHost: createYoloitMediaHost(),
      js3dHost: createYoloitCube3dHost(),
      imageResolver: createExternalImageResolver(widget.panel.state),
      onEvent: (actionId, payload) {
        setState(() {
          if (actionId == '_field') {
            final key = payload['key'] as String?;
            if (key != null && key.isNotEmpty) {
              _previewStorage = <String, dynamic>{
                ..._previewStorage,
                key: payload['value'],
              };
            }
            return;
          }
          final stateWithFields = UiViewBindings.withLiveFields(
            <String, dynamic>{
              '_storage': _previewStorage,
              '_scripts': _scripts,
            },
            _previewFieldRegistry,
          );
          final next = UiViewBindings.applyTap(
            state: stateWithFields,
            actionId: actionId,
            payload: payload,
            runScript: UiViewScriptRunner.instance.runAction,
          );
          _previewStorage = UiViewBindings.storageFromState(next);
        });
      },
    );
    _controller.addListener(_validateJson);
    _validateJson();
    _syncActionSelection(tree);
  }

  @override
  void dispose() {
    _controller.dispose();
    _scriptController.dispose();
    super.dispose();
  }

  void _syncActionSelection(Map<String, dynamic> tree) {
    final ids = UiViewActions.uniqueActionIds(
      UiViewActions.collectFromTree(tree),
    );
    if (ids.isEmpty) {
      _selectedActionId = null;
      _scriptController.text = '';
      return;
    }
    final selected =
        _selectedActionId != null && ids.contains(_selectedActionId)
            ? _selectedActionId!
            : ids.first;
    _selectedActionId = selected;
    _scriptController.text =
        _scripts[selected] ?? UiViewActions.defaultScript(selected);
  }

  void _persistCurrentScript() {
    final id = _selectedActionId;
    if (id == null) return;
    final text = _scriptController.text;
    if (text.trim().isEmpty) {
      _scripts.remove(id);
    } else {
      _scripts[id] = text;
    }
  }

  void _selectAction(String actionId) {
    if (_selectedActionId == actionId) return;
    _persistCurrentScript();
    setState(() {
      _selectedActionId = actionId;
      _scriptController.text =
          _scripts[actionId] ?? UiViewActions.defaultScript(actionId);
    });
  }

  void _setMode(_UiEditorMode mode) {
    if (_mode == mode) return;
    if (mode != _UiEditorMode.json) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
    if (_mode == _UiEditorMode.scripts) {
      _persistCurrentScript();
    }
    if (mode == _UiEditorMode.scripts) {
      final tree = _tryParseTree(_controller.text);
      if (tree != null) _syncActionSelection(tree);
    }
    setState(() => _mode = mode);
  }

  void _validateJson() {
    final error = _tryParseTree(_controller.text) == null ? 'Invalid JSON' : null;
    if (_parseError != error) {
      setState(() => _parseError = error);
    }
  }

  Map<String, dynamic>? _tryParseTree(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {}
    return null;
  }


  Widget _buildScriptsPane(BuildContext context, Map<String, dynamic> tree) {
    final colors = context.appColors;
    final refs = UiViewActions.collectFromTree(tree);
    final ids = UiViewActions.uniqueActionIds(refs);
    if (ids.isEmpty) {
      return Center(
        child: Text(
          'Нет кнопок с onTap в дереве. Добавьте в JSON:\n'
          '{"type":"button","data":"...","onTap":"myAction"}',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 12),
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SizedBox(
          width: 180,
          child: ListView.separated(
            itemCount: ids.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final id = ids[index];
              final ref = refs.firstWhere((item) => item.actionId == id);
              final selected = id == _selectedActionId;
              return Material(
                color: Colors.transparent,
                child: ListTile(
                  dense: true,
                  selected: selected,
                  title: Text(id, style: const TextStyle(fontSize: 12)),
                  subtitle: Text(
                    ref.label.isEmpty ? ref.nodeType : ref.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () => _selectAction(id),
                ),
              );
            },
          ),
        ),
        const VerticalDivider(width: 1),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Text(
                  'JavaScript для onTap: $_selectedActionId',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _scriptController,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.all(12),
                    hintText:
                        'storage.taps = (storage.taps || 0) + 1;\n'
                        'storage.message = payload.text;',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final rawTree = _tryParseTree(_controller.text);
    final previewTree =
        rawTree == null
            ? null
            : UiViewBindings.applyTree(rawTree, _previewStorage);
    return AlertDialog(
      title: const Text('UI View — JSON tree'),
      content: SizedBox(
        width: 720,
        height: 520,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SegmentedButton<_UiEditorMode>(
              segments: const <ButtonSegment<_UiEditorMode>>[
                ButtonSegment<_UiEditorMode>(
                  value: _UiEditorMode.json,
                  label: Text('JSON'),
                  icon: Icon(Icons.code_outlined, size: 16),
                ),
                ButtonSegment<_UiEditorMode>(
                  value: _UiEditorMode.preview,
                  label: Text('Preview'),
                  icon: Icon(Icons.visibility_outlined, size: 16),
                ),
                ButtonSegment<_UiEditorMode>(
                  value: _UiEditorMode.scripts,
                  label: Text('Scripts'),
                  icon: Icon(Icons.javascript_outlined, size: 16),
                ),
              ],
              selected: <_UiEditorMode>{_mode},
              onSelectionChanged: (selection) => _setMode(selection.first),
            ),
            if (_mode == _UiEditorMode.preview) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Preview с биндингами {{key}}. Логику кнопок редактируйте во вкладке Scripts.',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
            if (_mode == _UiEditorMode.scripts) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'JS для каждого onTap. Доступны: storage, payload, actionId. '
                'Без скрипта — дефолт (+1 taps). Полный widget.js → app:run.',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
              ),
            ],
            const SizedBox(height: 8),
            if (_parseError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _parseError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                  ),
                ),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: colors.border),
                  borderRadius: BorderRadius.circular(8),
                  color: colors.surface,
                ),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: switch (_mode) {
                    _UiEditorMode.preview => Scrollbar(
                      key: const ValueKey<String>('preview'),
                      thumbVisibility: true,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child:
                            previewTree == null
                                ? const Text('Fix JSON to preview')
                                : _previewRenderer.build(
                                  previewTree,
                                  context,
                                ),
                      ),
                    ),
                    _UiEditorMode.scripts =>
                      rawTree == null
                          ? const Center(
                            key: ValueKey<String>('scripts-invalid'),
                            child: Text('Fix JSON to edit scripts'),
                          )
                          : KeyedSubtree(
                            key: const ValueKey<String>('scripts'),
                            child: _buildScriptsPane(context, rawTree),
                          ),
                    _UiEditorMode.json => TextField(
                      key: const ValueKey<String>('editor'),
                      controller: _controller,
                      maxLines: null,
                      expands: true,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.all(12),
                        hintText: '{"type":"column","children":[...]}',
                      ),
                    ),
                  },
                ),
              ),
            ),
            if (rawTree != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Text: ${AppCliUtils.extractTextLines(rawTree).take(4).join(' · ')}',
                style: TextStyle(color: colors.textSecondary, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_previewStorage.isNotEmpty)
                Text(
                  'Storage: ${const JsonEncoder().convert(_previewStorage)}',
                  style: TextStyle(color: colors.textSecondary, fontSize: 11),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed:
              _parseError == null
                  ? () {
                    final parsed = _tryParseTree(_controller.text);
                    if (parsed == null) return;
                    _persistCurrentScript();
                    Navigator.of(context).pop(<String, dynamic>{
                      'tree': parsed,
                      if (_scripts.isNotEmpty) '_scripts': _scripts,
                    });
                  }
                  : null,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
