// ignore_for_file: unused_element
//
// ════════════════════════════════════════════════════════════════════════════
//  EXAMPLE PLUGIN — "Hello World" mindmap card
//  ─────────────────────────────────────────────────────────────────────────
//  This file is NOT registered at startup — it exists purely as a reference
//  implementation that third-party developers can copy.
//
//  To activate it (for testing):
//    MindMapPluginRegistry.instance.register(HelloWorldPlugin());
//  ════════════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';
import 'package:yoloit/features/mindmap/plugin/mindmap_card_plugin.dart';

// ── 1. Define your plugin class ────────────────────────────────────────────

class HelloWorldPlugin extends MindMapCardPlugin {
  // ── Identity ──────────────────────────────────────────────────────────────

  @override
  String get pluginId => 'com.example.hello-world';

  @override
  String get displayName => 'Hello World';

  @override
  IconData get icon => Icons.waving_hand_outlined;

  @override
  String get typeTag => 'hello';

  // ── Card behaviour ────────────────────────────────────────────────────────

  @override
  bool get isResizable => true;

  @override
  Size get minResizeSize => const Size(200, 120);

  // ── Rendering ─────────────────────────────────────────────────────────────

  @override
  Widget buildWidget(MindMapPluginNodeData data) {
    final title = data.payload['title'] as String? ?? 'Hello World';
    final body = data.payload['body'] as String? ?? 'A plugin card.';
    return _HelloWorldCard(title: title, body: body);
  }

  // ── Data provision ────────────────────────────────────────────────────────

  @override
  List<PluginNodeEntry> provideNodes(BuildContext context) {
    return [
      PluginNodeEntry(
        data: MindMapPluginNodeData(
          id: 'hello:main',
          pluginId: pluginId,
          columnIndex: 9,
          typeTag: typeTag,
          defaultSize: const Size(260, 160),
          payload: const {
            'title': 'Hello World',
            'body': 'This card is provided by the HelloWorldPlugin.',
          },
        ),
      ),
    ];
  }
}

class _HelloWorldCard extends StatelessWidget {
  const _HelloWorldCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Container(
      decoration: BoxDecoration(
        color: colors.background,
        border: Border.all(
          color: colors.accentOrange.withValues(alpha: 0.44),
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: colors.background.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                border: Border(
                  bottom: BorderSide(color: colors.border),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.waving_hand_outlined,
                    size: 12,
                    color: colors.accentOrange,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  body,
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 3. Registration (do this in main.dart or a plugin initialiser) ─────────
//
// void main() {
//   MindMapPluginRegistry.instance.register(HelloWorldPlugin());
//   runApp(const MyApp());
// }

// ── HOW A THIRD-PARTY PACKAGE WOULD DO IT ─────────────────────────────────
//
// A standalone Dart package `my_mindmap_plugin` would export:
//   - Its plugin class (implements MindMapCardPlugin)
//   - A top-level `void registerMyPlugin()` helper
//
// The host app adds the package to pubspec.yaml and calls:
//   registerMyPlugin();   // in main() before runApp
//
// No changes to the yoloit source code are needed.
//
// ── PLUGIN SDK SURFACE ─────────────────────────────────────────────────────
//
// Everything a plugin needs is exported from the mindmap feature:
//
//   package:yoloit/features/mindmap/plugin/mindmap_card_plugin.dart
//     └─ MindMapCardPlugin   (abstract class to implement)
//     └─ PluginNodeEntry     (returned by provideNodes)
//
//   package:yoloit/features/mindmap/plugin/mindmap_plugin_registry.dart
//     └─ MindMapPluginRegistry.instance.register(plugin)
//
//   package:yoloit/features/mindmap/model/mindmap_node_model.dart
//     └─ MindMapPluginNodeData   (the node data class to instantiate)
//     └─ MindMapConnection       (connection between two cards)
//     └─ ConnectorStyle          (solid / dashed / animated)
