// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web implementation that deletes all CacheStorage entries and reloads.
Future<void> clearWebPageCacheImpl() async {
  final cacheStorage = html.window.caches;
  if (cacheStorage != null) {
    final rawKeys = await cacheStorage.keys();
    final keys = (rawKeys as List<dynamic>).cast<String>();
    for (final key in keys) {
      await cacheStorage.delete(key);
    }
  }
  html.window.location.reload();
}
