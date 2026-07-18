import 'dart:async';

import 'package:flutter/material.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_base.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_engine_manager.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';
import 'package:yoloit/features/settings/data/global_env_groups_service.dart';
import 'package:yoloit/features/settings/ui/env_group_picker.dart';

final _customWidgetDarkFallbackColors = AppColorScheme.fromAccent(
  Colors.indigo,
);
final _customWidgetLightFallbackColors = AppColorScheme.fromAccent(
  Colors.indigo,
  brightness: Brightness.light,
);

class CustomWidgetContent extends StatefulWidget {
  const CustomWidgetContent({
    super.key,
    required this.panel,
    required this.renderContext,
    this.loadWidgets,
    this.engineManager,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  /// Optional override for loading the widget list; defaults to the singleton
  /// registry service. Used in tests to avoid touching the filesystem.
  final Future<List<WidgetManifest>> Function()? loadWidgets;

  /// Optional override for the widget engine manager; defaults to the singleton.
  final WidgetEngineManager? engineManager;

  @override
  State<CustomWidgetContent> createState() => _CustomWidgetContentState();
}

class _CustomWidgetContentState extends State<CustomWidgetContent> {
  JsWidgetEngine? _engine;
  JsonWidgetRenderer? _renderer;
  Map<String, dynamic>? _uiTree;

  bool _loading = true;
  String? _error;

  String get _widgetId => widget.panel.state['widgetId'] as String? ?? '';

  WidgetEngineManager get _engineManager =>
      widget.engineManager ?? WidgetEngineManager.instance;

  @override
  void initState() {
    super.initState();
    ThemeManager.instance.addListener(_onThemeChanged);
    if (_widgetId.isNotEmpty) {
      WidgetAppRegistry.instance.registerReload(
        _widgetId,
        _reloadCurrentWidget,
      );
    }
    final existing = _engineManager.engine(widget.panel.id);
    if (existing != null) {
      _engine = existing;
      _renderer = _buildRenderer(existing);
      _uiTree = _engineManager.tree(widget.panel.id);
      _loading = false;
      _error = null;
      unawaited(_load(keepExistingUi: true));
    } else {
      unawaited(_load());
    }
  }

  @override
  void didUpdateWidget(CustomWidgetContent old) {
    super.didUpdateWidget(old);
    final oldId = old.panel.state['widgetId'] as String? ?? '';
    if (_widgetId != oldId) {
      if (oldId.isNotEmpty) {
        WidgetAppRegistry.instance.unregister(
          oldId,
          engine: _engineManager.engine(widget.panel.id),
        );
      }
      if (_widgetId.isNotEmpty) {
        WidgetAppRegistry.instance.registerReload(
          _widgetId,
          _reloadCurrentWidget,
        );
      }
      unawaited(_load(forceReload: oldId.isNotEmpty));
      return;
    }
    final oldGroups = old.panel.state['_selectedEnvGroups'];
    final newGroups = widget.panel.state['_selectedEnvGroups'];
    final oldCustom = old.panel.state['_customEnvVars'];
    final newCustom = widget.panel.state['_customEnvVars'];
    if (oldGroups != newGroups || oldCustom != newCustom) {
      _applyEnvVarsAsync(widget.panel.state);
    }
  }

  @override
  void dispose() {
    HeadlessRenderRegistry.activeTasks.remove('widget:${widget.panel.id}');
    ThemeManager.instance.removeListener(_onThemeChanged);
    _engineManager.remove(widget.panel.id);
    super.dispose();
  }

  void _onThemeChanged() {
    final engine = _engine;
    if (engine != null) {
      engine.updateTheme(_themeColors());
      if (mounted) {
        setState(() => _renderer = _buildRenderer(engine));
      }
    }
  }

  Map<String, dynamic> _themeColors() {
    final tm = ThemeManager.instance;
    final scheme = tm.theme.extension<AppColorScheme>();
    final isDark = tm.isDark;
    final fallbackScheme =
        isDark
            ? _customWidgetDarkFallbackColors
            : _customWidgetLightFallbackColors;
    return {
      'isDark': isDark,
      'bg': _hexColor(scheme?.background ?? fallbackScheme.background),
      'surface': _hexColor(scheme?.surface ?? fallbackScheme.surface),
      'border': _hexColor(scheme?.border ?? fallbackScheme.border),
      'accent': _hexColor(scheme?.primary ?? fallbackScheme.primary),
      'text': _hexColor(scheme?.textPrimary ?? fallbackScheme.textPrimary),
      'muted': _hexColor(scheme?.textSecondary ?? fallbackScheme.textSecondary),
    };
  }

  JsonWidgetTheme _jsonWidgetTheme() {
    final tm = ThemeManager.instance;
    final scheme = tm.theme.extension<AppColorScheme>();
    final isDark = tm.isDark;
    final fallback =
        isDark
            ? _customWidgetDarkFallbackColors
            : _customWidgetLightFallbackColors;
    return JsonWidgetTheme(
      primary: scheme?.primary ?? fallback.primary,
      divider: scheme?.border ?? fallback.border,
      surface: scheme?.surface ?? fallback.surface,
      text: scheme?.textPrimary ?? fallback.textPrimary,
      muted: scheme?.textSecondary ?? fallback.textSecondary,
    );
  }

  String _hexColor(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  void _applyEnvVars(JsWidgetEngine engine, Map<String, dynamic> state) {
    final legacy = state['_envGroup'] as Map?;
    final custom =
        (state['_customEnvVars'] as Map?)?.cast<String, String>() ?? {};
    if (legacy != null && state['_selectedEnvGroups'] == null) {
      _engineManager.applyEnvVars(
        widget.panel.id,
        {...legacy.cast<String, String>(), ...custom},
      );
      return;
    }
    _engineManager.applyEnvVars(widget.panel.id, custom);
    _applyEnvVarsAsync(state, engine: engine);
  }

  Future<void> _applyEnvVarsAsync(
    Map<String, dynamic> state, {
    JsWidgetEngine? engine,
  }) async {
    final eng = engine ?? _engine;
    if (eng == null) return;
    final selectedGroups =
        (state['_selectedEnvGroups'] as List?)?.whereType<String>().toList() ??
        [];
    final custom =
        (state['_customEnvVars'] as Map?)?.cast<String, String>() ?? {};
    final groupVars =
        selectedGroups.isEmpty
            ? <String, String>{}
            : await GlobalEnvGroupsService.instance.resolveSelectedGroups(
              selectedGroups,
            );
    if (!mounted) return;
    _engineManager.applyEnvVars(widget.panel.id, {...groupVars, ...custom});
  }

  Future<void> _reloadCurrentWidget() => _load(forceReload: true);

  void _handleRenderedTree(Map<String, dynamic> tree) {
    if (!mounted) return;
    HeadlessRenderRegistry.activeTasks.remove('widget:${widget.panel.id}');
    setState(() => _uiTree = tree);
  }

  JsonWidgetRenderer _buildRenderer(JsWidgetEngine engine) {
    return JsonWidgetRenderer(
      theme: _jsonWidgetTheme(),
      onEvent: (actionId, payload) {
        unawaited(engine.callEvent(actionId, payload));
      },
    );
  }

  Future<void> _load({
    bool forceReload = false,
    bool keepExistingUi = false,
  }) async {
    final taskKey = 'widget:${widget.panel.id}';
    if (_widgetId.isNotEmpty) {
      HeadlessRenderRegistry.activeTasks.add(taskKey);
    }

    if (!keepExistingUi) {
      _engine = null;
      _renderer = null;
      _uiTree = null;
    }

    if (_widgetId.isEmpty) {
      _engineManager.remove(widget.panel.id);
      HeadlessRenderRegistry.activeTasks.remove(taskKey);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      return;
    }

    if (forceReload) {
      _engineManager.remove(widget.panel.id);
    }

    if (!keepExistingUi && mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final engine = await _engineManager.getOrCreate(
        panelId: widget.panel.id,
        widgetId: _widgetId,
        panel: widget.panel,
        initialTheme: _themeColors(),
        onRenderUI: _handleRenderedTree,
      );
      if (engine == null) {
        HeadlessRenderRegistry.activeTasks.remove(taskKey);
        if (mounted) {
          setState(() {
            _loading = false;
            _error = 'Widget "$_widgetId" not found';
          });
        }
        return;
      }

      _applyEnvVars(engine, widget.panel.state);
      _engine = engine;
      _renderer = _buildRenderer(engine);
      final tree = _engineManager.tree(widget.panel.id);
      if (tree != null) {
        HeadlessRenderRegistry.activeTasks.remove(taskKey);
      }
      if (mounted) {
        setState(() {
          _uiTree = tree ?? _uiTree;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      HeadlessRenderRegistry.activeTasks.remove(taskKey);
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return _ErrorView(error: _error!, onRetry: _load);
    }
    if (_widgetId.isEmpty) {
      return _PickerView(
        panel: widget.panel,
        renderContext: widget.renderContext,
        loadWidgets: widget.loadWidgets,
      );
    }
    final tree = _uiTree;
    if (tree == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return ClipRect(child: _renderer!.build(tree, context));
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.accentRed, size: 32),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.accentRed, fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

class _PickerView extends StatefulWidget {
  const _PickerView({
    required this.panel,
    required this.renderContext,
    this.loadWidgets,
  });
  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  final Future<List<WidgetManifest>> Function()? loadWidgets;

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
  List<WidgetManifest>? _widgets;

  @override
  void initState() {
    super.initState();
    final loader = widget.loadWidgets ??
        () => WidgetRegistryService.instance.loadAll();
    loader().then((list) {
      if (mounted) setState(() => _widgets = list);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final widgets = _widgets;
    if (widgets == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (widgets.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.widgets_outlined, size: 40),
              const SizedBox(height: 12),
              Text(
                'No widgets installed.',
                style: TextStyle(
                  color: cs.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Run: yoloit widget:list',
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: widgets.length,
      separatorBuilder: (_, index) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final m = widgets[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final createPanel = widget.renderContext.onCreateLinkedPanel;
            if (createPanel != null) {
              createPanel(CustomWidgetPluginBase.kTypeId, {
                'widgetId': m.id,
              }, m.name);
            } else {
              widget.renderContext.onUpdateState({
                ...widget.panel.state,
                'widgetId': m.id,
              });
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cs.outlineVariant),
            ),
            child: Row(
              children: [
                Text(m.icon, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        m.name,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      if (m.description.isNotEmpty)
                        Text(
                          m.description,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontSize: 11,
                          ),
                        ),
                    ],
                  ),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  size: 12,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class CustomWidgetCliHandler extends PanelCliHandler {
  const CustomWidgetCliHandler();

  @override
  String get typeId => CustomWidgetPluginBase.kTypeId;

  @override
  List<String> get supportedActions => const [
    'setState',
    'info',
    'execute',
    'snapshot',
  ];

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'execute': const CliActionHelp(
      description:
          'Send a JS event to the widget (same as yoloit app:execute)',
      params: {
        'actionId': 'Event id from app:help (alias: action)',
        'payload': 'JSON object passed to the handler',
      },
      example:
          'yoloit do "<board>" "<panel>" execute \'{"actionId":"set_city","payload":{"city":"Grodno"}}\'',
    ),
    'snapshot': const CliActionHelp(
      description: 'Return the current declarative UI render tree',
    ),
    'info': const CliActionHelp(
      description: 'Return widget id and manifest metadata',
    ),
    'setState': const CliActionHelp(
      description: 'Replace persisted widget panel state',
      params: {'state': 'JSON object merged into panel state'},
    ),
  };

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) => {
    'widgetId': panel.state['widgetId'] ?? '',
  };

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'setState':
        final state = args['state'] as Map?;
        if (state == null) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "state" field',
          );
        }
        return CliActionResult(
          ok: true,
          message: 'State updated',
          stateUpdate: Map<String, dynamic>.from(state),
        );
      case 'info':
        final wid = panel.state['widgetId'] as String? ?? '';
        final manifest =
            wid.isNotEmpty
                ? await WidgetRegistryService.instance.find(wid)
                : null;
        return CliActionResult(
          ok: true,
          data: {'widgetId': wid, 'manifest': manifest?.toJson()},
        );
      case 'execute':
        final widgetId = panel.state['widgetId'] as String? ?? '';
        final actionId =
            (args['actionId'] ?? args['action']) as String?;
        if (actionId == null || actionId.trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "actionId" field (alias: action)',
          );
        }
        final payload = args['payload'] as Map<String, dynamic>?;
        final engine = WidgetEngineManager.instance.engine(panel.id);
        if (engine == null) {
          return CliActionResult(
            ok: false,
            message: 'Widget "$widgetId" is not currently running',
          );
        }
        await engine.callEvent(actionId, payload);
        final exported = engine.exportedState;
        return CliActionResult(
          ok: true,
          message: 'Event "$actionId" sent to widget "$widgetId"',
          data: {
            'widgetId': widgetId,
            'actionId': actionId,
            if (exported != null) 'state': exported,
          },
        );
      case 'snapshot':
        final widgetId = panel.state['widgetId'] as String? ?? '';
        final tree = WidgetEngineManager.instance.tree(panel.id);
        if (tree == null) {
          return CliActionResult(
            ok: false,
            message: 'No render tree available for widget "$widgetId"',
          );
        }
        return CliActionResult(
          ok: true,
          data: {'widgetId': widgetId, 'tree': tree},
        );
    }
    return CliActionResult(ok: false, message: 'Unknown action: $action');
  }
}

class QuickSizeButton extends StatelessWidget {
  const QuickSizeButton({required this.onResize});
  final void Function(double w, double h) onResize;

  static const _sizes = [
    (icon: Icons.crop_free_outlined, label: 'Compact', w: 360.0, h: 420.0),
    (icon: Icons.smartphone_outlined, label: 'Mobile', w: 390.0, h: 844.0),
    (icon: Icons.tablet_outlined, label: 'Tablet', w: 768.0, h: 1024.0),
    (
      icon: Icons.desktop_windows_outlined,
      label: 'Desktop',
      w: 1280.0,
      h: 800.0,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: PopupMenuButton<({double w, double h})>(
        tooltip: 'Quick size',
        padding: EdgeInsets.zero,
        iconSize: 14,
        icon: Icon(
          Icons.aspect_ratio_outlined,
          size: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant.withAlpha(150),
        ),
        onSelected: (s) => onResize(s.w, s.h),
        itemBuilder:
            (_) =>
                _sizes
                    .map(
                      (s) => PopupMenuItem(
                        value: (w: s.w, h: s.h),
                        height: 36,
                        child: Row(
                          children: [
                            Icon(s.icon, size: 14),
                            const SizedBox(width: 8),
                            Text(
                              '${s.label} (${s.w.toInt()}×${s.h.toInt()})',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    )
                    .toList(),
      ),
    );
  }
}

class EnvGearButton extends StatelessWidget {
  const EnvGearButton({required this.panel, required this.onUpdate});
  final BoardPanelInstance panel;

  /// Called with (selectedGroupIds, customVars)
  final void Function(
    List<String> selectedGroups,
    Map<String, dynamic> customVars,
  )
  onUpdate;

  bool get _hasEnv {
    final groups = panel.state['_selectedEnvGroups'] as List?;
    final custom = panel.state['_customEnvVars'] as Map?;
    final legacy = panel.state['_envGroup'] as Map?;
    return (groups?.isNotEmpty == true) ||
        (custom?.isNotEmpty == true) ||
        (legacy?.isNotEmpty == true);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return SizedBox(
      width: 24,
      height: 24,
      child: IconButton(
        padding: EdgeInsets.zero,
        iconSize: 14,
        tooltip: 'Environment variables',
        icon: Icon(
          Icons.settings_outlined,
          color:
              _hasEnv
                  ? colors.accentGreen
                  : Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withAlpha(120),
        ),
        onPressed: () => _showEnvDialog(context),
      ),
    );
  }

  void _showEnvDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => _EnvDialog(panel: panel, onUpdate: onUpdate),
    );
  }
}

class _EnvDialog extends StatefulWidget {
  const _EnvDialog({required this.panel, required this.onUpdate});
  final BoardPanelInstance panel;
  final void Function(List<String>, Map<String, dynamic>) onUpdate;

  @override
  State<_EnvDialog> createState() => _EnvDialogState();
}

class _EnvDialogState extends State<_EnvDialog> {
  late List<String> _selectedGroups;
  late List<MapEntry<String, String>> _customRows;

  @override
  void initState() {
    super.initState();
    final raw = widget.panel.state['_selectedEnvGroups'];
    _selectedGroups = (raw as List?)?.whereType<String>().toList() ?? [];

    final customRaw = widget.panel.state['_customEnvVars'] as Map?;
    if (customRaw != null) {
      _customRows =
          customRaw.entries
              .map((e) => MapEntry(e.key.toString(), e.value.toString()))
              .toList();
    } else {
      final legacy = widget.panel.state['_envGroup'] as Map?;
      _customRows =
          legacy?.entries
              .map((e) => MapEntry(e.key.toString(), e.value.toString()))
              .toList() ??
          [];
    }
  }

  void _addRow() => setState(() => _customRows.add(const MapEntry('', '')));

  void _removeRow(int i) => setState(() => _customRows.removeAt(i));

  void _updateKey(int i, String v) {
    setState(() {
      _customRows[i] = MapEntry(v, _customRows[i].value);
    });
  }

  void _updateVal(int i, String v) {
    setState(() {
      _customRows[i] = MapEntry(_customRows[i].key, v);
    });
  }

  void _save() {
    final customVars = <String, dynamic>{
      for (final e in _customRows)
        if (e.key.trim().isNotEmpty) e.key.trim(): e.value,
    };
    widget.onUpdate(_selectedGroups, customVars);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return AlertDialog(
      title: const Text(
        'Environment Variables',
        style: TextStyle(fontSize: 14),
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Env Group Presets',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Select global groups from Settings → Environment',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 8),
              EnvGroupSelectionField(
                selectedGroupIds: _selectedGroups,
                onChanged: (ids) => setState(() => _selectedGroups = ids),
                label: '',
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text(
                    'Custom Variables',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: onSurface,
                    ),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _addRow,
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Overrides group values. Injected into jsr.exec().',
                style: TextStyle(fontSize: 11, color: muted),
              ),
              const SizedBox(height: 8),
              ..._customRows.asMap().entries.map((entry) {
                final i = entry.key;
                final e = entry.value;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: e.key)
                            ..selection = TextSelection.collapsed(
                              offset: e.key.length,
                            ),
                          onChanged: (v) => _updateKey(i, v),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'KEY',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text('=', style: TextStyle(fontSize: 12)),
                      const SizedBox(width: 4),
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: TextEditingController(text: e.value)
                            ..selection = TextSelection.collapsed(
                              offset: e.value.length,
                            ),
                          onChanged: (v) => _updateVal(i, v),
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          decoration: const InputDecoration(
                            hintText: 'value',
                            border: OutlineInputBorder(),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => _removeRow(i),
                        icon: const Icon(Icons.close, size: 14),
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            setState(() {
              _selectedGroups = [];
              _customRows = [];
            });
          },
          child: const Text('Clear All'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
