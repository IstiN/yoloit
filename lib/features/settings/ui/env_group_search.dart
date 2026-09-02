import 'package:yoloit/features/settings/data/global_env_groups_service.dart';

/// A group matched by the env quick search together with the entries that
/// should stay visible for it.
class EnvGroupSearchResult {
  const EnvGroupSearchResult({required this.group, required this.entries});

  final GlobalEnvGroup group;

  /// Entries visible under the current query. When the query matched the
  /// group name only, this is the full entry list.
  final List<MapEntry<String, String>> entries;
}

/// Case-insensitive substring search across env group names and variable
/// keys, shared by the settings section and the group picker.
class EnvGroupSearch {
  const EnvGroupSearch._();

  /// Filters [groups] by [query].
  ///
  /// An empty query returns every group with all of its entries. When a
  /// group name matches, all of its entries are kept; otherwise only the
  /// groups with at least one matching key are returned and only the
  /// matching entries are kept. Keys rejected by [isDraftKey] (not yet
  /// named by the user) never match.
  static List<EnvGroupSearchResult> filter(
    List<GlobalEnvGroup> groups,
    String query, {
    bool Function(String key)? isDraftKey,
  }) {
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) {
      return <EnvGroupSearchResult>[
        for (final group in groups)
          EnvGroupSearchResult(
            group: group,
            entries: group.values.entries.toList(),
          ),
      ];
    }
    final results = <EnvGroupSearchResult>[];
    for (final group in groups) {
      if (group.name.toLowerCase().contains(needle)) {
        results.add(
          EnvGroupSearchResult(
            group: group,
            entries: group.values.entries.toList(),
          ),
        );
        continue;
      }
      final matched =
          group.values.entries
              .where((entry) {
                if (isDraftKey != null && isDraftKey(entry.key)) {
                  return false;
                }
                return entry.key.toLowerCase().contains(needle);
              })
              .toList();
      if (matched.isNotEmpty) {
        results.add(EnvGroupSearchResult(group: group, entries: matched));
      }
    }
    return results;
  }
}
