import 'dart:convert';

import 'package:yoloit/core/platform/file_storage_adapter.dart';

/// Describes a custom JS widget stored under a base path.
///
/// On VM the base path is a directory path; on web it is a virtual prefix
/// (e.g. `widgets/<id>`) managed by [FileStorageAdapter]. All internal paths
/// use forward slashes.
class WidgetManifest {
  const WidgetManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.icon,
    required this.allowedCommands,
    required this.networkEnabled,
    required this.widgetPath,
    required this.isSingleFile,
    this.files,
    this.cli,
  });

  /// Unique identifier (directory name or file stem).
  final String id;

  /// Human-readable name shown in the panel catalog.
  final String name;

  final String description;
  final String version;

  /// Emoji or short label used as the icon.
  final String icon;

  /// CLI commands this widget is allowed to call via `window.yoloit.cli()`.
  /// Empty list means no CLI access. Use ["*"] to allow all (dev only).
  final List<String> allowedCommands;

  /// Whether the widget JS may make network requests (fetch/XHR).
  /// Currently informational — enforced by Content Security Policy.
  final bool networkEnabled;

  /// Base path to the widget directory (or the .js file if single-file).
  /// Uses forward slashes on both VM and web.
  final String widgetPath;

  /// True when the widget is a single .js file without a directory.
  final bool isSingleFile;

  /// Explicit ordered list of JS files to concatenate (relative to widgetPath).
  /// When null or empty, falls back to reading widget.js.
  final List<String>? files;

  /// Optional CLI help for agents: events, examples, read-state hints.
  final Map<String, dynamic>? cli;

  /// Virtual path to the main widget.js entry point.
  String get mainJsPath => isSingleFile ? widgetPath : '$widgetPath/widget.js';

  /// Parent directory of the entry point.
  String get appDir {
    if (isSingleFile) {
      final idx = widgetPath.lastIndexOf('/');
      if (idx <= 0) return widgetPath;
      return widgetPath.substring(0, idx);
    }
    return widgetPath;
  }

  /// Reads and returns the JS source code.
  ///
  /// If [files] is set, reads each file in order and concatenates them.
  /// Otherwise falls back to reading widget.js.
  /// After assembling, runs the [_preprocessIncludes] pass which inlines
  /// `yoloit.include('path')` calls with the referenced file contents.
  Future<String?> readJs({FileStorageAdapter? adapter}) async {
    final storage = adapter ?? FileStorageAdapter.instance;
    final base = widgetPath;
    late final String js;

    if (files != null && files!.isNotEmpty) {
      final parts = <String>[];
      for (final filename in files!) {
        final path = '$base/$filename';
        final content = await storage.readString(path);
        if (content != null) {
          parts.add(content);
        } else {
          parts.add('/* yoloit.include: file not found: $filename */');
        }
      }
      js = parts.join('\n');
    } else {
      final content = await storage.readString(mainJsPath);
      if (content == null) return null;
      js = content;
    }

    return _preprocessIncludes(js, appDir, 0, storage);
  }

  /// Recursively inlines `yoloit.include('path')` calls (up to [_maxIncludeDepth]).
  static const int _maxIncludeDepth = 5;
  static final RegExp _includeRegex = RegExp(
    r'''yoloit\.include\(\s*['"]([^'"]+)['"]\s*\)''',
  );

  static Future<String> _preprocessIncludes(
    String source,
    String baseDir,
    int depth,
    FileStorageAdapter storage,
  ) async {
    if (depth >= _maxIncludeDepth) return source;
    if (!_includeRegex.hasMatch(source)) return source;

    final buffer = StringBuffer();
    var last = 0;
    for (final match in _includeRegex.allMatches(source)) {
      buffer.write(source.substring(last, match.start));
      final relPath = match.group(1)!;
      final absPath = '$baseDir/$relPath';
      final content = await storage.readString(absPath);
      if (content != null) {
        final subDir = _parentOf(absPath);
        buffer.write(
          await _preprocessIncludes(content, subDir, depth + 1, storage),
        );
      } else {
        buffer.write('/* yoloit.include: file not found: $relPath */');
      }
      last = match.end;
    }
    buffer.write(source.substring(last));
    return buffer.toString();
  }

  static String _parentOf(String path) {
    final idx = path.lastIndexOf('/');
    if (idx <= 0) return path;
    return path.substring(0, idx);
  }

  static String _normalizePath(String path) => path.replaceAll('\\', '/');

  static String _lastSegment(String path) {
    final normalized = _normalizePath(path);
    final parts = normalized.split('/');
    return parts.isEmpty ? normalized : parts.last;
  }

  /// Creates a manifest from a storage base path (directory).
  static Future<WidgetManifest?> fromStorage(
    String basePath, {
    FileStorageAdapter? adapter,
  }) async {
    final storage = adapter ?? FileStorageAdapter.instance;
    final normalized = _normalizePath(basePath);
    final jsPath = '$normalized/widget.js';
    if (!await storage.exists(jsPath)) return null;

    final id = _lastSegment(normalized);
    final manifestPath = '$normalized/manifest.json';
    final manifestRaw = await storage.readString(manifestPath);
    if (manifestRaw != null) {
      try {
        final raw = jsonDecode(manifestRaw) as Map<String, dynamic>;
        final filesList = raw['files'] as List?;
        final cliRaw = raw['cli'];
        return WidgetManifest(
          id: (raw['id'] as String? ?? id).trim(),
          name: (raw['name'] as String? ?? id),
          description: raw['description'] as String? ?? '',
          version: raw['version'] as String? ?? '1.0.0',
          icon: raw['icon'] as String? ?? '🔧',
          allowedCommands: List<String>.from(
            raw['allowedCommands'] as List? ?? [],
          ),
          networkEnabled: raw['network'] as bool? ?? true,
          widgetPath: normalized,
          isSingleFile: false,
          files: filesList != null ? List<String>.from(filesList) : null,
          cli:
              cliRaw is Map
                  ? Map<String, dynamic>.from(cliRaw)
                  : null,
        );
      } catch (_) {}
    }

    // No manifest — derive defaults from directory name.
    return WidgetManifest(
      id: id,
      name: _titleCase(id),
      description: '',
      version: '1.0.0',
      icon: '🔧',
      allowedCommands: const [],
      networkEnabled: true,
      widgetPath: normalized,
      isSingleFile: false,
    );
  }

  /// Creates a manifest from a single .js file path.
  static WidgetManifest fromJsFilePath(
    String filePath, {
    FileStorageAdapter? adapter,
  }) {
    final normalized = _normalizePath(filePath);
    final stem = _lastSegment(normalized).replaceAll('.js', '');
    return WidgetManifest(
      id: stem,
      name: _titleCase(stem),
      description: '',
      version: '1.0.0',
      icon: '🔧',
      allowedCommands: const [],
      networkEnabled: true,
      widgetPath: normalized,
      isSingleFile: true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'icon': icon,
    'allowedCommands': allowedCommands,
    'network': networkEnabled,
    'widgetPath': widgetPath,
    'isSingleFile': isSingleFile,
    if (files != null) 'files': files,
    if (cli != null) 'cli': cli,
  };

  static String _titleCase(String s) =>
      s.replaceAll(RegExp(r'[-_]'), ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}
