import 'package:yoloit/features/board/widgets/js_widget_engine.dart';

/// Singleton that tracks currently active [JsWidgetEngine] instances.
/// [_CustomWidgetContentState] registers/unregisters on load/dispose.
class WidgetAppRegistry {
  static final instance = WidgetAppRegistry._();
  WidgetAppRegistry._();

  final Map<String, _WidgetAppEntry> _entries = {};

  void register(String widgetId, JsWidgetEngine engine, Map<String, dynamic>? tree) {
    final existing = _entries[widgetId];
    _entries[widgetId] = _WidgetAppEntry(engine, tree, existing?.reloadCallback);
  }

  /// Register a callback that reloads the widget panel (called by CLI reload).
  void registerReload(String widgetId, Future<void> Function() callback) {
    final entry = _entries[widgetId];
    if (entry != null) {
      entry.reloadCallback = callback;
    } else {
      // Pre-register before engine is ready
      _entries[widgetId] = _WidgetAppEntry(null, null, callback);
    }
  }

  void updateTree(String widgetId, Map<String, dynamic> tree) {
    final entry = _entries[widgetId];
    if (entry != null) entry.tree = tree;
  }

  void unregister(String widgetId) {
    _entries.remove(widgetId);
  }

  JsWidgetEngine? engine(String widgetId) => _entries[widgetId]?.engine;
  Map<String, dynamic>? tree(String widgetId) => _entries[widgetId]?.tree;
  List<String> activeIds() => _entries.keys.toList();

  /// Returns true if a reload was triggered, false if widget is not running.
  Future<bool> triggerReload(String widgetId) async {
    final cb = _entries[widgetId]?.reloadCallback;
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
