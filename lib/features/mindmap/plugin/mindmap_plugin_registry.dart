import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/plugin/mindmap_card_plugin.dart';

/// Global registry for all mindmap card plugins.
///
/// Register at app startup (before the first frame):
/// ```dart
/// void main() {
///   MindMapPluginRegistry.instance
///     ..register(MyPlugin())
///     ..register(AnotherPlugin());
///   runApp(const MyApp());
/// }
/// ```
class MindMapPluginRegistry {
  MindMapPluginRegistry._();

  static final instance = MindMapPluginRegistry._();

  final _plugins = <String, MindMapCardPlugin>{};

  // ── Registration ──────────────────────────────────────────────────────────

  /// Register a plugin. If a plugin with the same [pluginId] is already
  /// registered it will be replaced.
  MindMapPluginRegistry register(MindMapCardPlugin plugin) {
    _plugins[plugin.pluginId] = plugin;
    return this;
  }

  /// Unregister a plugin by id.
  void unregister(String pluginId) => _plugins.remove(pluginId);

  // ── Queries ───────────────────────────────────────────────────────────────

  /// All registered plugins, insertion-ordered.
  List<MindMapCardPlugin> get all => List.unmodifiable(_plugins.values);

  /// Look up a plugin by its id — null if not registered.
  MindMapCardPlugin? forId(String pluginId) => _plugins[pluginId];

  // ── Canvas integration ────────────────────────────────────────────────────

  /// Build the card widget for a [MindMapPluginNodeData] node.
  /// Falls back to [_UnknownPluginCard] if the plugin is not registered.
  Widget buildWidget(MindMapPluginNodeData data) {
    final plugin = _plugins[data.pluginId];
    if (plugin == null) return _UnknownPluginCard(data: data);
    return plugin.buildWidget(data);
  }

  /// Whether the card for [data] is resizable.
  bool isResizable(MindMapPluginNodeData data) =>
      _plugins[data.pluginId]?.isResizable ?? true;

  /// Minimum resize size for the card carrying [data].
  Size minResizeSize(MindMapPluginNodeData data) =>
      _plugins[data.pluginId]?.minResizeSize ?? const Size(200, 120);

  /// Collect all nodes (and connections) from every registered plugin.
  /// Called by the canvas's [_buildData] every time the canvas rebuilds.
  List<({MindMapPluginNodeData data, List<MindMapConnection> connections})>
      collectNodes(BuildContext context) {
    final result =
        <({MindMapPluginNodeData data, List<MindMapConnection> connections})>[];
    for (final plugin in _plugins.values) {
      try {
        for (final entry in plugin.provideNodes(context)) {
          result.add((data: entry.data, connections: entry.connections));
        }
      } catch (e, st) {
        debugPrint(
          '[MindMapPluginRegistry] ${plugin.pluginId} provideNodes() threw: '
          '$e\n$st',
        );
      }
    }
    return result;
  }

  /// Sidebar group descriptors from all registered plugins.
  List<({String tag, String label, IconData icon})> get sidebarGroups => [
        for (final p in _plugins.values)
          (tag: p.typeTag, label: p.displayName, icon: p.icon),
      ];
}

class _UnknownPluginCard extends StatelessWidget {
  const _UnknownPluginCard({required this.data});

  final MindMapPluginNodeData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border.all(
          color: colors.primaryDark.withValues(alpha: 0.55),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.extension_off,
            color: colors.primaryDark,
            size: 20,
          ),
          const SizedBox(height: 8),
          Text(
            'Plugin not installed',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            data.pluginId,
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
