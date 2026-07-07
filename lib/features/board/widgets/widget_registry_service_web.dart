import 'package:flutter/services.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/widgets/widget_manifest.dart';

/// Discovers and manages custom JS apps stored in [FileStorageAdapter]
/// under the `widgets/` prefix.
///
/// On first run the service copies bundled example apps from Flutter assets
/// (`tools/widgets/`) into browser storage.
class WidgetRegistryService {
  WidgetRegistryService._({FileStorageAdapter? adapter})
    : _adapter = adapter ?? FileStorageAdapter.instance;

  static final instance = WidgetRegistryService._();

  /// Test hook with a fake storage adapter.
  factory WidgetRegistryService.testInstance({FileStorageAdapter? adapter}) =
      WidgetRegistryService._;

  final FileStorageAdapter _adapter;

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
    return WidgetManifest.fromStorage(base, adapter: _adapter);
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
        adapter: _adapter,
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

  /// Copy bundled example widgets from Flutter assets on first run.
  Future<void> _ensureExamplesInstalled() async {
    final existing = await _adapter.list(_prefix);
    if (existing.isNotEmpty) return;

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
