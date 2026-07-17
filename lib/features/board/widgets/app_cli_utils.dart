import 'package:js_widget_runtime/js_widget_runtime.dart';

/// Shared helpers for YoLoIT app CLI (`app:help`, `app:state`, `app:snapshot`).
class AppCliUtils {
  const AppCliUtils._();

  static const globalCommands = <Map<String, String>>[
    {'cmd': 'app:list', 'desc': 'List installed apps and which are running'},
    {'cmd': 'app:run <id>', 'desc': 'Open app in a new panel'},
    {'cmd': 'app:help <id>', 'desc': 'Show CLI commands/events for this app'},
    {'cmd': 'app:state <id>', 'desc': 'Read structured state + visible text'},
    {'cmd': 'app:snapshot <id>', 'desc': 'Full JSON render tree'},
    {'cmd': 'app:execute <id> <event> [json]', 'desc': 'Fire a UI event'},
    {'cmd': 'app:reload <id>', 'desc': 'Hot-reload widget.js from disk'},
    {'cmd': 'app:logs <id>', 'desc': 'Read console.log output'},
  ];

  /// Normalize an app id, absolute path, or directory basename.
  static String basename(String idOrPath) {
    if (!idOrPath.contains('/')) return idOrPath;
    return idOrPath.split('/').last;
  }

  /// Collect human-readable text from a declarative render tree.
  static List<String> extractTextLines(Map<String, dynamic> node) {
    final lines = <String>[];
    void walk(Object? value) {
      if (value is Map<String, dynamic>) {
        final data = value['data'];
        if (data is String) {
          final trimmed = data.trim();
          if (trimmed.isNotEmpty) lines.add(trimmed);
        }
        final text = value['text'];
        if (text is String) {
          final trimmed = text.trim();
          if (trimmed.isNotEmpty) lines.add(trimmed);
        }
        final label = value['label'];
        if (label is String) {
          final trimmed = label.trim();
          if (trimmed.isNotEmpty) lines.add(trimmed);
        }
        final title = value['title'];
        if (title is String) {
          final trimmed = title.trim();
          if (trimmed.isNotEmpty) lines.add(trimmed);
        }
        final subtitle = value['subtitle'];
        if (subtitle is String) {
          final trimmed = subtitle.trim();
          if (trimmed.isNotEmpty) lines.add(trimmed);
        }
        for (final child in value.values) {
          if (child is List) {
            for (final item in child) {
              walk(item);
            }
          } else if (child is Map) {
            walk(Map<String, dynamic>.from(child));
          }
        }
      } else if (value is List) {
        for (final item in value) {
          walk(item);
        }
      }
    }

    walk(node);
    return lines;
  }

  static Map<String, dynamic> buildHelp({
    required WidgetManifest manifest,
    required bool running,
  }) {
    final cli = manifest.cli;
    return {
      'id': manifest.id,
      'name': manifest.name,
      'description': manifest.description,
      'running': running,
      'network': manifest.networkEnabled,
      'globalCommands': globalCommands,
      ...? cli,
      'examples': _examplesFor(manifest.id, cli),
    };
  }

  static List<String> _examplesFor(
    String id,
    Map<String, dynamic>? cli,
  ) {
    final fromManifest = cli?['examples'];
    if (fromManifest is List) {
      return fromManifest.map((e) => e.toString()).toList(growable: false);
    }
    return [
      'yoloit app:run $id',
      'yoloit app:help $id',
      'yoloit app:state $id',
      'yoloit app:snapshot $id',
    ];
  }
}
