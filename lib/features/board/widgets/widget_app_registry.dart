import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/app_cli_utils.dart';

/// Singleton that tracks currently active [JsWidgetEngine] instances.
/// [WidgetEngineManager] registers and unregisters engines as panel lifecycles change.
class WidgetAppRegistry {
  static final instance = WidgetAppRegistry._();
  WidgetAppRegistry._();

  /// Creates an isolated instance for unit testing.
  factory WidgetAppRegistry.testInstance() => WidgetAppRegistry._();

  final Map<String, _WidgetAppEntry> _entries = {};
  final Map<String, String> _aliases = {};

  void register(
    String widgetId,
    JsWidgetEngine engine,
    Map<String, dynamic>? tree,
  ) {
    final existing = _entries[widgetId];
    _entries[widgetId] = _WidgetAppEntry(
      engine,
      tree,
      existing?.reloadCallback,
    );
  }

  void registerAlias(String alias, String canonicalId) {
    if (alias == canonicalId) return;
    _aliases[alias] = canonicalId;
    final base = AppCliUtils.basename(alias);
    if (base != alias && base != canonicalId) {
      _aliases[base] = canonicalId;
    }
  }

  String resolveLookupKey(String idOrPath) {
    if (_entries.containsKey(idOrPath)) return idOrPath;
    final aliased = _aliases[idOrPath];
    if (aliased != null && _entries.containsKey(aliased)) return aliased;
    final base = AppCliUtils.basename(idOrPath);
    if (_entries.containsKey(base)) return base;
    final baseAlias = _aliases[base];
    if (baseAlias != null && _entries.containsKey(baseAlias)) return baseAlias;
    return idOrPath;
  }

  /// Register a callback that reloads the widget panel (called by CLI reload).
  void registerReload(String widgetId, Future<void> Function() callback) {
    final key = resolveLookupKey(widgetId);
    final entry = _entries[key];
    if (entry != null) {
      entry.reloadCallback = callback;
    } else {
      // Pre-register before engine is ready
      _entries[key] = _WidgetAppEntry(null, null, callback);
    }
  }

  void updateTree(String widgetId, Map<String, dynamic> tree) {
    final key = resolveLookupKey(widgetId);
    final entry = _entries[key];
    if (entry != null) entry.tree = tree;
  }

  void unregister(String widgetId, {JsWidgetEngine? engine}) {
    final key = resolveLookupKey(widgetId);
    final entry = _entries[key];
    if (entry == null) return;
    if (engine != null && !identical(entry.engine, engine)) return;
    _entries.remove(key);
    _aliases.removeWhere((_, value) => value == key);
  }

  JsWidgetEngine? engine(String widgetId) =>
      _entries[resolveLookupKey(widgetId)]?.engine;
  Map<String, dynamic>? tree(String widgetId) =>
      _entries[resolveLookupKey(widgetId)]?.tree;
  List<String> activeIds() => _entries.keys.toList();

  /// Returns true if a reload was triggered, false if widget is not running.
  Future<bool> triggerReload(String widgetId) async {
    final key = resolveLookupKey(widgetId);
    final cb = _entries[key]?.reloadCallback;
    if (cb == null) return false;
    await cb();
    return true;
  }
}

class _WidgetAppEntry {
  _WidgetAppEntry(this.engine, this.tree, this.reloadCallback);
  final JsWidgetEngine? engine;
  Map<String, dynamic>? tree;
  Future<void> Function()? reloadCallback;
}
