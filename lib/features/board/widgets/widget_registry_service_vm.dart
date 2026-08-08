import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/features/board/widgets/widget_file_reader_vm.dart';

/// Discovers and manages custom JS apps installed in
/// `~/.config/yoloit/apps/`.
///
/// On first run the service copies the bundled example apps from Flutter
/// assets (`tools/widgets/`) into the user's app directory.
class WidgetRegistryService {
  WidgetRegistryService._();
  static final instance = WidgetRegistryService._();

  List<WidgetManifest>? _cache;

  final WidgetFileReader _reader = VmWidgetFileReader.instance;

  /// Test seam: overrides the home directory used by [appsDir] and `~`
  /// expansion so unit tests can point the registry at a temp directory.
  @visibleForTesting
  static String? debugHomeDir;

  static String get _home => debugHomeDir ?? Platform.environment['HOME'] ?? '';

  String get appsDir {
    return '$_home/.config/yoloit/apps';
  }

  /// Backward-compat alias.
  String get widgetsDir => appsDir;

  /// Returns all installed widgets, scanning the widgets directory.
  /// Results are cached until [invalidate] is called.
  Future<List<WidgetManifest>> loadAll() async {
    if (_cache != null) return _cache!;
    await _ensureExamplesInstalled();
    _cache = await _scan();
    return _cache!;
  }

  /// Find a widget by id or by absolute/relative path.
  /// If [id] is an absolute path to a directory containing widget.js,
  /// it is loaded directly without installing — ideal for local development.
  Future<WidgetManifest?> find(String id) async {
    // Treat absolute paths as direct local-dev mounts (no install needed).
    if (id.startsWith('/') || id.startsWith('~')) {
      final resolved = id.startsWith('~')
          ? id.replaceFirst('~', _home)
          : id;
      final dir = Directory(resolved);
      if (await dir.exists()) {
        final m = await WidgetManifest.fromStorage(_normalize(dir.path), reader: _reader);
        if (m != null) return m;
      }
      return null;
    }
    final all = await loadAll();
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Clears the in-memory cache so the next [loadAll] re-scans.
  void invalidate() => _cache = null;

  /// Install a widget from a local directory or .js file path.
  /// Returns the installed manifest on success.
  Future<WidgetManifest?> install(String sourcePath) async {
    final source = FileSystemEntity.typeSync(sourcePath);
    final destDir = Directory(appsDir);
    if (!destDir.existsSync()) destDir.createSync(recursive: true);

    if (source == FileSystemEntityType.directory) {
      final dir = Directory(sourcePath);
      final name = dir.path.split(Platform.pathSeparator).last;
      final dest = Directory('${destDir.path}${Platform.pathSeparator}$name');
      // If source is already inside appsDir (same path), skip copy — already installed.
      if (dest.path == dir.path || dest.path == dir.path.trimRight()) {
        invalidate();
        return WidgetManifest.fromStorage(_normalize(dest.path), reader: _reader);
      }
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      await _copyDir(dir, dest);
      invalidate();
      return WidgetManifest.fromStorage(_normalize(dest.path), reader: _reader);
    } else if (source == FileSystemEntityType.file &&
        sourcePath.endsWith('.js')) {
      final file = File(sourcePath);
      final name = file.path.split(Platform.pathSeparator).last;
      final dest = File('${destDir.path}${Platform.pathSeparator}$name');
      if (dest.path != file.path) await file.copy(dest.path);
      invalidate();
      return WidgetManifest.fromJsFilePath(_normalize(dest.path));
    }
    return null;
  }

  /// Web-only file installation; unsupported on VM.
  Future<WidgetManifest?> installFromFiles({
    required String id,
    required Map<String, String> files,
  }) async => null;

  /// Remove a widget by id.
  Future<bool> remove(String id) async {
    final manifest = await find(id);
    if (manifest == null) return false;
    if (manifest.isSingleFile) {
      await File(manifest.widgetPath).delete();
    } else {
      await Directory(manifest.widgetPath).delete(recursive: true);
    }
    invalidate();
    return true;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  static String _normalize(String path) => path.replaceAll('\\', '/');

  Future<List<WidgetManifest>> _scan() async {
    final dir = Directory(appsDir);
    if (!await dir.exists()) return [];

    final results = <WidgetManifest>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) {
        final m = await WidgetManifest.fromStorage(_normalize(entity.path), reader: _reader);
        if (m != null) results.add(m);
      } else if (entity is File && entity.path.endsWith('.js')) {
        results.add(WidgetManifest.fromJsFilePath(_normalize(entity.path)));
      }
    }
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  /// Copy bundled example widgets from Flutter assets on first run.
  Future<void> _ensureExamplesInstalled() async {
    final destDir = Directory(appsDir);
    if (!destDir.existsSync()) {
      destDir.createSync(recursive: true);
    }

    // Always overwrite bundled example widgets so updates ship with the app.
    const examples = [
      'weather',
      'crypto',
      'stocks',
      'calculator',
      'yolo-hello',
      'animation-showcase',
      '3d-showcase',
      '3d-glb-showcase',
    ];
    for (final name in examples) {
      final dest = Directory(
        '${destDir.path}${Platform.pathSeparator}$name',
      );
      dest.createSync(recursive: true);
      for (final filename in ['manifest.json', 'widget.js']) {
        try {
          final assetKey = 'tools/widgets/$name/$filename';
          final data = await rootBundle.load(assetKey);
          final bytes = data.buffer.asUint8List();
          await File(
            '${dest.path}${Platform.pathSeparator}$filename',
          ).writeAsBytes(bytes);
        } catch (_) {
          // Asset not bundled — skip silently.
        }
      }
    }
  }

  Future<void> _copyDir(Directory src, Directory dest) async {
    dest.createSync(recursive: true);
    await for (final entity in src.list()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        await _copyDir(
          entity,
          Directory('${dest.path}${Platform.pathSeparator}$name'),
        );
      } else if (entity is File) {
        await entity.copy('${dest.path}${Platform.pathSeparator}$name');
      }
    }
  }
}
