import 'dart:convert';
import 'dart:io';

/// Describes a custom JS widget installed in ~/.config/yoloit/widgets/.
///
/// A widget is either:
///   - A **directory** with a `manifest.json` + `widget.js`
///   - A **single .js file** (manifest fields inferred from filename)
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

  /// Absolute path to the widget directory (or the .js file if single-file).
  final String widgetPath;

  /// True when the widget is a single .js file without a directory.
  final bool isSingleFile;

  /// Explicit ordered list of JS files to concatenate (relative to widgetPath).
  /// When null or empty, falls back to reading widget.js.
  final List<String>? files;

  /// Absolute path to the main widget.js entry point.
  String get mainJsPath =>
      isSingleFile ? widgetPath : '$widgetPath${Platform.pathSeparator}widget.js';

  /// App directory (parent directory of the entry point for single-file apps).
  String get appDir =>
      isSingleFile ? File(widgetPath).parent.path : widgetPath;

  /// Reads and returns the JS source code.
  ///
  /// If [files] is set, reads each file in order and concatenates them.
  /// Otherwise falls back to reading widget.js.
  /// After assembling, runs the [_preprocessIncludes] pass which inlines
  /// `yoloit.include('path')` calls with the referenced file contents.
  Future<String?> readJs() async {
    String js;

    if (files != null && files!.isNotEmpty) {
      final parts = <String>[];
      for (final filename in files!) {
        final path = '$widgetPath${Platform.pathSeparator}${filename.replaceAll('/', Platform.pathSeparator)}';
        final file = File(path);
        if (await file.exists()) {
          parts.add(await file.readAsString());
        } else {
          parts.add('/* yoloit.include: file not found: $filename */');
        }
      }
      js = parts.join('\n');
    } else {
      final file = File(mainJsPath);
      if (!await file.exists()) return null;
      js = await file.readAsString();
    }

    return _preprocessIncludes(js, widgetPath, 0);
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
  ) async {
    if (depth >= _maxIncludeDepth) return source;
    if (!_includeRegex.hasMatch(source)) return source;

    final buffer = StringBuffer();
    int last = 0;
    for (final match in _includeRegex.allMatches(source)) {
      buffer.write(source.substring(last, match.start));
      final relPath = match.group(1)!;
      final absPath = '$baseDir${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}';
      final file = File(absPath);
      if (await file.exists()) {
        final included = await file.readAsString();
        final subDir = File(absPath).parent.path;
        buffer.write(await _preprocessIncludes(included, subDir, depth + 1));
      } else {
        buffer.write('/* yoloit.include: file not found: $relPath */');
      }
      last = match.end;
    }
    buffer.write(source.substring(last));
    return buffer.toString();
  }

  /// Creates a manifest from a directory (reads manifest.json if present).
  static Future<WidgetManifest?> fromDirectory(Directory dir) async {
    final jsFile = File('${dir.path}${Platform.pathSeparator}widget.js');
    if (!await jsFile.exists()) return null;

    final id = dir.path.split(Platform.pathSeparator).last;
    final manifestFile = File(
      '${dir.path}${Platform.pathSeparator}manifest.json',
    );

    if (await manifestFile.exists()) {
      try {
        final raw = jsonDecode(await manifestFile.readAsString()) as Map<String, dynamic>;
        final filesList = raw['files'] as List?;
        return WidgetManifest(
          id: (raw['id'] as String? ?? id).trim(),
          name: (raw['name'] as String? ?? id),
          description: raw['description'] as String? ?? '',
          version: raw['version'] as String? ?? '1.0.0',
          icon: raw['icon'] as String? ?? '🔧',
          allowedCommands: List<String>.from(raw['allowedCommands'] as List? ?? []),
          networkEnabled: raw['network'] as bool? ?? true,
          widgetPath: dir.path,
          isSingleFile: false,
          files: filesList != null ? List<String>.from(filesList) : null,
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
      widgetPath: dir.path,
      isSingleFile: false,
    );
  }

  /// Creates a manifest from a single .js file.
  static WidgetManifest fromJsFile(File file) {
    final stem = file.path
        .split(Platform.pathSeparator)
        .last
        .replaceAll('.js', '');
    return WidgetManifest(
      id: stem,
      name: _titleCase(stem),
      description: '',
      version: '1.0.0',
      icon: '🔧',
      allowedCommands: const [],
      networkEnabled: true,
      widgetPath: file.path,
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
  };

  static String _titleCase(String s) =>
      s.replaceAll(RegExp(r'[-_]'), ' ').split(' ').map((w) {
        if (w.isEmpty) return w;
        return w[0].toUpperCase() + w.substring(1);
      }).join(' ');
}
