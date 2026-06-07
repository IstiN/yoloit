import 'dart:io';

/// Lightweight entry describing one file-system child of a directory.
class DirectoryEntry {
  const DirectoryEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
  });

  final String name;
  final String path;
  final bool isDirectory;
}

/// Builds a map of unique root paths from [candidates].
///
/// Each candidate is trimmed; null, empty, or duplicate values are skipped.
Map<String, String> buildUniqueRoots(Map<String, String?> candidates) {
  final seen = <String>{};
  final result = <String, String>{};
  for (final entry in candidates.entries) {
    final value = entry.value?.trim();
    if (value == null || value.isEmpty || !seen.add(value)) continue;
    result[entry.key] = value;
  }
  return result;
}

/// Lists the immediate children of [directory] that are files or directories.
///
/// Entries are sorted: directories first, then alphabetically by name
/// (case-insensitive).
Future<List<DirectoryEntry>> listDirectoryEntries(Directory directory) async {
  final entries = <DirectoryEntry>[];
  await for (final entity in directory.list(followLinks: false)) {
    final stat = await entity.stat();
    if (stat.type != FileSystemEntityType.directory &&
        stat.type != FileSystemEntityType.file) {
      continue;
    }
    entries.add(DirectoryEntry(
      name: entity.path.split('/').last,
      path: entity.path,
      isDirectory: stat.type == FileSystemEntityType.directory,
    ));
  }
  entries.sort((a, b) {
    if (a.isDirectory != b.isDirectory) {
      return a.isDirectory ? -1 : 1;
    }
    return a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return entries;
}
