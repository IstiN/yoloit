import 'package:flutter/material.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/calendar_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/chart_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/checklist_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/code_snippet_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/diff_preview_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/files_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/filetree_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/kanban_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/run_configs_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/setup_guide_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/table_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/webpage_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin.dart';
import 'package:yoloit/ui/components/typography/caption.dart';

/// Global registry for [BoardPanelPlugin] implementations.
///
/// Built-in plugins are pre-registered. Third-party or app-specific plugins
/// can be added at startup:
/// ```dart
/// void main() {
///   BoardPluginRegistry.instance.register(MyCustomPlugin());
///   runApp(const App());
/// }
/// ```
class BoardPluginRegistry {
  BoardPluginRegistry._() {
    _registerBuiltins();
  }

  static final BoardPluginRegistry _instance = BoardPluginRegistry._();
  static BoardPluginRegistry get instance => _instance;

  final Map<String, BoardPanelPlugin> _plugins = {};

  // ── Registration ──────────────────────────────────────────────────────────

  /// Register a plugin. Overwrites any existing plugin with the same [typeId].
  void register(BoardPanelPlugin plugin) {
    _plugins[plugin.typeId] = plugin;
  }

  // ── Lookup ─────────────────────────────────────────────────────────────────

  /// Returns the plugin for [typeId], or `null` if not registered.
  BoardPanelPlugin? pluginFor(String typeId) => _plugins[typeId];

  /// Returns a fallback plugin for unknown panel types.
  BoardPanelPlugin get fallback => const _UnknownPanelPlugin();

  /// All registered plugins in registration order.
  List<BoardPanelPlugin> get all => List.unmodifiable(_plugins.values);

  /// All plugins that should appear in the board catalog
  /// (i.e. those that are visible to the user when adding a new panel).
  List<BoardPanelPlugin> get catalogPlugins =>
      all.where((plugin) => plugin.showInCatalog).toList();

  /// Catalog plugins that are actually supported on the current runtime.
  ///
  /// Unsupported plugins are still registered (so existing boards load them as
  /// placeholders) but are hidden from the Add Panel catalog.
  List<BoardPanelPlugin> get catalogPluginsForCurrentPlatform => catalogPlugins
      .where((plugin) => plugin.isSupportedOnCurrentPlatform)
      .toList();

  // ── Internals ──────────────────────────────────────────────────────────────

  void _registerBuiltins() {
    register(const MarkdownNotePlugin());
    register(const StickyNotePlugin());
    register(const ShapePlugin());
    register(const KanbanPlugin());
    register(const WebpagePlugin());
    register(const CodeSnippetPlugin());
    register(const ChecklistPlugin());
    register(const CalendarPlugin());
    register(const TablePlugin());
    register(const ChartPlugin());
    register(const FilesPlugin());
    register(const FilePreviewPlugin());
    register(const PlaylistPlugin());
    register(const RunPlugin());
    register(const RunConfigsPlugin());
    register(const SetupGuidePlugin());
    register(const ChatPanelPlugin());
    register(const BoardTerminalPanelPlugin());
    register(const FileTreePlugin());
    register(const DiffPreviewPlugin());
    register(const YoloAssistantPlugin());
    register(const CustomWidgetPlugin());
    register(const UiViewPlugin());
    register(const TimerPlugin());
  }
}

// ---------------------------------------------------------------------------
// Fallback plugin for unrecognised type IDs (e.g. from a newer app version).
// ---------------------------------------------------------------------------

class _UnknownPanelPlugin extends BoardPanelPlugin {
  const _UnknownPanelPlugin();

  @override
  String get typeId => '__unknown__';

  @override
  String get displayName => 'Unknown Panel';

  @override
  IconData get icon => const IconData(0xe5c9, fontFamily: 'MaterialIcons');

  @override
  Widget buildContent(context, panel, renderContext) {
    return Center(
      child: Caption('Unknown panel type: ${panel.type}', textAlign: TextAlign.center, fontSize: 12),
    );
  }
}
