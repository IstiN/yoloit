import 'package:yoloit/features/board/widgets/widget_manifest.dart';

/// Web placeholder for [WidgetRegistryService].
///
/// Custom JS widgets are a desktop feature because they require a real file
/// system for installation and discovery. On web, the registry is always empty
/// and install/remove/find are no-ops.
class WidgetRegistryService {
  WidgetRegistryService._();
  static final instance = WidgetRegistryService._();

  List<WidgetManifest>? _cache;

  String get appsDir => '';

  /// Backward-compat alias.
  String get widgetsDir => appsDir;

  /// Returns an empty list on web.
  Future<List<WidgetManifest>> loadAll() async {
    _cache ??= const [];
    return _cache!;
  }

  /// Always returns null on web.
  Future<WidgetManifest?> find(String id) async => null;

  /// Clears the in-memory cache.
  void invalidate() => _cache = null;

  /// Always returns null on web.
  Future<WidgetManifest?> install(String sourcePath) async => null;

  /// Always returns false on web.
  Future<bool> remove(String id) async => false;
}
