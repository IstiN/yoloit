import 'package:yoloit/features/board/widgets/js_widget_engine.dart';

/// Singleton that tracks currently active [JsWidgetEngine] instances.
/// [_CustomWidgetContentState] registers/unregisters on load/dispose.
class WidgetAppRegistry {
  static final instance = WidgetAppRegistry._();
  WidgetAppRegistry._();

  final Map<String, _WidgetAppEntry> _entries = {};

  void register(String widgetId, JsWidgetEngine engine, Map<String, dynamic>? tree) {
    _entries[widgetId] = _WidgetAppEntry(engine, tree);
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
}

class _WidgetAppEntry {
  final JsWidgetEngine engine;
  Map<String, dynamic>? tree;
  _WidgetAppEntry(this.engine, this.tree);
}
