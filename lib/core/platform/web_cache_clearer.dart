import 'package:flutter/foundation.dart';

import 'web_cache_clearer_vm.dart'
    if (dart.library.html) 'web_cache_clearer_web.dart';

/// Clears the browser's CacheStorage entries and reloads the page.
///
/// No-op on non-web platforms.
Future<void> clearWebPageCache() async {
  if (!kIsWeb) return;
  await clearWebPageCacheImpl();
}
