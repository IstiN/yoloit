/// Shared helpers for CLI route handlers.
library;

import 'package:shelf/shelf.dart' as shelf;

/// Common dependencies passed to board sub-route handlers.
typedef BoardRouteDependencies = ({
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
  shelf.Response Function(String) notFound,
  void Function() scheduleRebuild,
});

/// Parses a comma-separated string or a list of strings into a list of panel
/// ids, filtering out empty values.
List<String> parsePanelIds(dynamic value) {
  if (value == null) return const [];
  if (value is String) {
    return value
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  if (value is List) {
    return value.whereType<String>().toList();
  }
  return const [];
}
