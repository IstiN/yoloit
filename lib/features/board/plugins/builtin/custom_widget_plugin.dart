import 'package:flutter/material.dart';
import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/widgets/js_widget_engine.dart';
import 'package:yoloit/features/board/widgets/json_widget_renderer.dart';
import 'package:yoloit/features/board/widgets/widget_app_registry.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';
import 'package:yoloit/features/board/widgets/widget_registry_service.dart';

class CustomWidgetPlugin extends BoardPanelPlugin {
  const CustomWidgetPlugin();

  static const String kTypeId = 'board.widget.custom';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Custom Widget';

  @override
  IconData get icon => Icons.widgets_outlined;

  @override
  Color get accentColor => const Color(0xFF7C3AED);

  @override
  Size get defaultSize => const Size(360, 420);

  @override
  Map<String, dynamic> get initialState => {
    'widgetId': '',
    'config': <String, dynamic>{},
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) {
    return _CustomWidgetContent(panel: panel, renderContext: renderContext);
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _CustomWidgetContent extends StatefulWidget {
  const _CustomWidgetContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_CustomWidgetContent> createState() => _CustomWidgetContentState();
}

class _CustomWidgetContentState extends State<_CustomWidgetContent> {
  JsWidgetEngine? _engine;
  JsonWidgetRenderer? _renderer;
  Map<String, dynamic>? _uiTree;

  WidgetManifest? _manifest;
  bool _loading = true;
  String? _error;

  String get _widgetId => widget.panel.state['widgetId'] as String? ?? '';

  @override
  void initState() {
    super.initState();
    ThemeManager.instance.addListener(_onThemeChanged);
    // Register reload callback immediately so CLI can trigger reload even before first load completes
    if (_widgetId.isNotEmpty) {
      WidgetAppRegistry.instance.registerReload(_widgetId, _load);
    }
    _load();
  }

  @override
  void didUpdateWidget(_CustomWidgetContent old) {
    super.didUpdateWidget(old);
    final oldId = old.panel.state['widgetId'] as String? ?? '';
    if (_widgetId != oldId) {
      if (_widgetId.isNotEmpty) {
        WidgetAppRegistry.instance.registerReload(_widgetId, _load);
      }
      _load();
    }
  }

  @override
  void dispose() {
    ThemeManager.instance.removeListener(_onThemeChanged);
    if (_widgetId.isNotEmpty) WidgetAppRegistry.instance.unregister(_widgetId);
    _engine?.dispose();
    super.dispose();
  }

  void _onThemeChanged() => _engine?.updateTheme(_themeColors());

  Map<String, dynamic> _themeColors() {
    final tm = ThemeManager.instance;
    final scheme = tm.theme.extension<AppColorScheme>();
    final isDark = tm.isDark;
    return {
      'isDark': isDark,
      'bg': _hexColor(scheme?.background ?? (isDark ? const Color(0xFF0f172a) : Colors.white)),
      'surface': _hexColor(scheme?.surface ?? (isDark ? const Color(0xFF1e293b) : const Color(0xFFF8FAFC))),
      'border': _hexColor(scheme?.border ?? (isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0))),
      'accent': _hexColor(scheme?.primary ?? const Color(0xFF818cf8)),
      'text': _hexColor(isDark ? const Color(0xFFf1f5f9) : const Color(0xFF1A1A2E)),
      'muted': _hexColor(isDark ? const Color(0xFF64748b) : const Color(0xFF94A3B8)),
    };
  }

  String _hexColor(Color c) {
    final r = (c.r * 255).round();
    final g = (c.g * 255).round();
    final b = (c.b * 255).round();
    return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
  }

  Future<void> _load() async {
    await _engine?.dispose();
    _engine = null;
    _renderer = null;
    _uiTree = null;

    if (_widgetId.isEmpty) {
      if (mounted) setState(() { _loading = false; _error = null; });
      return;
    }

    if (mounted) setState(() { _loading = true; _error = null; });

    final manifest = await WidgetRegistryService.instance.find(_widgetId);
    if (manifest == null) {
      if (mounted) setState(() { _loading = false; _error = 'Widget "$_widgetId" not found'; });
      return;
    }

    final js = await manifest.readJs();
    if (js == null) {
      if (mounted) setState(() { _loading = false; _error = 'widget.js missing for "$_widgetId"'; });
      return;
    }

    final storage = Map<String, dynamic>.from(
      widget.panel.state['_storage'] as Map? ?? {},
    );

    final engine = JsWidgetEngine(
      widgetId: _widgetId,
      appDir: manifest.appDir,
      onRender: (tree) {
        if (mounted) setState(() => _uiTree = tree);
        WidgetAppRegistry.instance.updateTree(_widgetId, tree);
      },
      onSetTitle: (title) {
        widget.renderContext.onUpdateState({
          ...widget.panel.state,
          '_title': title,
        });
      },
      onStorageUpdate: (newStorage) {
        widget.renderContext.onUpdateState({
          ...widget.panel.state,
          '_storage': newStorage,
        });
      },
      initialStorage: storage,
      initialTheme: _themeColors(),
    );

    _renderer = JsonWidgetRenderer(
      onEvent: (actionId, payload) => engine.callEvent(actionId, payload),
    );

    try {
      await engine.run(js);
      _engine = engine;
      WidgetAppRegistry.instance.register(_widgetId, engine, null);
      WidgetAppRegistry.instance.registerReload(_widgetId, _load);
      if (mounted) setState(() { _manifest = manifest; _loading = false; });
    } catch (e) {
      engine.dispose();
      if (mounted) setState(() { _loading = false; _error = 'Failed to run widget: $e'; });
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
      return _PickerView(panel: widget.panel, renderContext: widget.renderContext);
    }
    final tree = _uiTree;
    if (tree == null) {
      // Engine running but no render yet
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: _renderer!.build(tree, context),
    );
  }
}

// ─── Error view ───────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});
  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Color(0xFFF87171), size: 32),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFFF87171), fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

// ─── Widget picker ────────────────────────────────────────────────────────────

class _PickerView extends StatefulWidget {
  const _PickerView({required this.panel, required this.renderContext});
  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_PickerView> createState() => _PickerViewState();
}

class _PickerViewState extends State<_PickerView> {
  List<WidgetManifest>? _widgets;

  @override
  void initState() {
    super.initState();
    WidgetRegistryService.instance.loadAll().then((list) {
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
                style: TextStyle(color: cs.onSurface, fontSize: 14, fontWeight: FontWeight.w600),
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
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (context, i) {
        final m = widgets[i];
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
              final createPanel = widget.renderContext.onCreateLinkedPanel;
              if (createPanel != null) {
                // Open widget as a new panel on the board
                createPanel(CustomWidgetPlugin.kTypeId, {'widgetId': m.id}, m.name);
              } else {
                // Fallback: replace current panel's content
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
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 11),
                        ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 12, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── CLI handler ──────────────────────────────────────────────────────────────

class CustomWidgetCliHandler extends PanelCliHandler {
  const CustomWidgetCliHandler();

  @override
  String get typeId => CustomWidgetPlugin.kTypeId;

  @override
  List<String> get supportedActions => const ['setState', 'info', 'execute', 'snapshot'];

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
        if (state == null) return const CliActionResult(ok: false, message: 'Missing "state" field');
        return CliActionResult(ok: true, message: 'State updated', stateUpdate: Map<String, dynamic>.from(state));
      case 'info':
        final wid = panel.state['widgetId'] as String? ?? '';
        final manifest = wid.isNotEmpty ? await WidgetRegistryService.instance.find(wid) : null;
        return CliActionResult(ok: true, data: {'widgetId': wid, 'manifest': manifest?.toJson()});
      case 'execute':
        final widgetId = panel.state['widgetId'] as String? ?? '';
        final actionId = args['actionId'] as String?;
        if (actionId == null) return const CliActionResult(ok: false, message: 'Missing "actionId" field');
        final payload = args['payload'] as Map<String, dynamic>?;
        final engine = WidgetAppRegistry.instance.engine(widgetId);
        if (engine == null) {
          return CliActionResult(ok: false, message: 'Widget "$widgetId" is not currently running');
        }
        engine.callEvent(actionId, payload);
        return CliActionResult(ok: true, message: 'Event "$actionId" sent to widget "$widgetId"');
      case 'snapshot':
        final widgetId = panel.state['widgetId'] as String? ?? '';
        final tree = WidgetAppRegistry.instance.tree(widgetId);
        if (tree == null) {
          return CliActionResult(ok: false, message: 'No render tree available for widget "$widgetId"');
        }
        return CliActionResult(ok: true, data: {'widgetId': widgetId, 'tree': tree});
    }
    return CliActionResult(ok: false, message: 'Unknown action: $action');
  }
}
