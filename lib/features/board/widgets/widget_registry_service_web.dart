import 'package:flutter/services.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/widget_file_reader_web.dart';
import 'package:yoloit/features/board/widgets/widget_remote_source.dart';

/// Discovers and manages custom JS apps stored in [FileStorageAdapter]
/// under the `widgets/` prefix.
///
/// On first run the service tries to fetch the built-in example widgets from
/// the GitHub raw-content URL (so the web demo always has the latest examples
/// without a full rebuild). If the network request fails, it falls back to the
/// bundled Flutter assets (`tools/widgets/`).
class WidgetRegistryService {
  WidgetRegistryService._({
    FileStorageAdapter? adapter,
    this._remoteSource,
  }) : _adapter = adapter ?? FileStorageAdapter.instance,
       _reader = WebWidgetFileReader(adapter: adapter);

  static final instance = WidgetRegistryService._();

  /// Test hook with a fake storage adapter / remote source.
  factory WidgetRegistryService.testInstance({
    FileStorageAdapter? adapter,
    WidgetRemoteSource? remoteSource,
  }) => WidgetRegistryService._(
        adapter: adapter,
        remoteSource: remoteSource,
      );

  final FileStorageAdapter _adapter;
  final WidgetFileReader _reader;
  final WidgetRemoteSource? _remoteSource;

  static const _prefix = 'widgets/';

  List<WidgetManifest>? _cache;

  String get appsDir => _prefix;

  /// Backward-compat alias.
  String get widgetsDir => appsDir;

  /// Returns all installed widgets from browser storage.
  /// Results are cached until [invalidate] is called.
  Future<List<WidgetManifest>> loadAll() async {
    if (_cache != null) return _cache!;
    await _ensureExamplesInstalled();
    _cache = await _scan();
    return _cache!;
  }

  /// Find a widget by id.
  Future<WidgetManifest?> find(String id) async {
    final all = await loadAll();
    for (final m in all) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// Clears the in-memory cache so the next [loadAll] re-scans.
  void invalidate() => _cache = null;

  /// Install from a local filesystem path is not supported on web.
  Future<WidgetManifest?> install(String sourcePath) async => null;

  /// Install a widget by writing files directly into browser storage.
  Future<WidgetManifest?> installFromFiles({
    required String id,
    required Map<String, String> files,
  }) async {
    final base = '$_prefix${id.trim()}';
    for (final entry in files.entries) {
      final path = '$base/${entry.key}';
      await _adapter.writeString(path, entry.value);
    }
    invalidate();
    return WidgetManifest.fromStorage(base, reader: _reader);
  }

  /// Remove a widget by id.
  Future<bool> remove(String id) async {
    final prefix = '$_prefix${id.trim()}/';
    final paths = await _adapter.list(prefix);
    if (paths.isEmpty) return false;
    for (final path in paths) {
      await _adapter.delete(path);
    }
    invalidate();
    return true;
  }

  // ── Internals ─────────────────────────────────────────────────────────────

  Future<List<WidgetManifest>> _scan() async {
    final paths = await _adapter.list(_prefix);
    final ids = _widgetIdsFromPaths(paths);
    final results = <WidgetManifest>[];
    for (final id in ids) {
      final m = await WidgetManifest.fromStorage(
        '$_prefix$id',
        reader: _reader,
      );
      if (m != null) results.add(m);
    }
    results.sort((a, b) => a.name.compareTo(b.name));
    return results;
  }

  Set<String> _widgetIdsFromPaths(List<String> paths) {
    final ids = <String>{};
    for (final path in paths) {
      if (!path.startsWith(_prefix)) continue;
      final remainder = path.substring(_prefix.length);
      final slash = remainder.indexOf('/');
      final id = slash < 0 ? remainder : remainder.substring(0, slash);
      if (id.isNotEmpty) ids.add(id);
    }
    return ids;
  }

  /// Ensures built-in example widgets exist in browser storage.
  ///
  /// First tries the configured remote source (GitHub raw). If that yields no
  /// widgets, falls back to bundled Flutter assets.
  Future<void> _ensureExamplesInstalled() async {
    final existing = await _adapter.list(_prefix);
    if (existing.isNotEmpty) return;

    final remote = _remoteSource ?? WidgetRemoteSource();
    final remoteWidgets = await remote.fetchAllExamples();
    if (remoteWidgets.isNotEmpty) {
      for (final entry in remoteWidgets.entries) {
        final id = entry.key;
        final files = entry.value;
        await installFromFiles(id: id, files: files);
      }
      return;
    }

    await _ensureExamplesFromAssets();
  }

  /// Copy bundled example widgets from Flutter assets.
  Future<void> _ensureExamplesFromAssets() async {
    const examples = [
      'weather',
      'crypto',
      'stocks',
      'calculator',
      'yolo-hello',
      'animation-showcase',
    ];
    for (final name in examples) {
      final base = '$_prefix$name';
      for (final filename in ['manifest.json', 'widget.js']) {
        try {
          final assetKey = 'tools/widgets/$name/$filename';
          final data = await rootBundle.load(assetKey);
          final bytes = data.buffer.asUint8List();
          await _adapter.writeBytes('$base/$filename', bytes);
        } catch (_) {
          // Asset not bundled — skip silently.
        }
      }
    }
  }
}
