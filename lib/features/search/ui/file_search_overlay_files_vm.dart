import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/features/search/data/file_search_service.dart';
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';

/// Information about a file discovered during quick-open search.
class FileSearchFileInfo {
  FileSearchFileInfo({
    required this.name,
    required this.relativePath,
    required this.filePath,
  });

  final String name;
  final String relativePath;
  final String filePath;
}

/// Resolves a path that may start with `~/` using the user's HOME directory.
String resolveFilePath(String input) {
  if (input.startsWith('~/')) {
    final home = Platform.environment['HOME'];
    if (home != null && home.isNotEmpty) {
      return p.join(home, input.substring(2));
    }
  }
  return input;
}

/// Returns whether [path] points to an existing file.
Future<bool> fileExists(String path) async {
  try {
    return await File(path).exists();
  } catch (_) {
    return false;
  }
}

/// Searches [roots] recursively for files whose names match [queries].
Future<List<FileSearchFileInfo>> collectMatchingFiles(
  List<String> roots,
  List<String> queries, {
  required int maxResults,
}) async {
  final results = <FileSearchFileInfo>[];
  for (final root in roots) {
    if (results.length >= maxResults) break;
    final dir = Directory(root);
    if (!await dir.exists()) continue;
    await _collectMatchingFiles(
      dir,
      root,
      queries,
      results,
      maxResults: maxResults,
    );
  }
  return results;
}

Future<void> _collectMatchingFiles(
  Directory dir,
  String root,
  List<String> queries,
  List<FileSearchFileInfo> results, {
  required int maxResults,
}) async {
  if (results.length >= maxResults) return;
  var visited = 0;
  try {
    await for (final entity in dir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (results.length >= maxResults) return;
      if (++visited % 80 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      final name = p.basename(entity.path);
      if (name.startsWith('.')) continue;
      if (entity is File && FuzzyMatcher.bestScore(name, queries) != null) {
        final relPath = p.relative(entity.path, from: root);
        // Avoid duplicates
        if (!results.any((r) => r.filePath == entity.path)) {
          results.add(
            FileSearchFileInfo(
              name: name,
              relativePath: relPath,
              filePath: entity.path,
            ),
          );
        }
      }
    }
  } on FileSystemException {
    // skip inaccessible
  }
}

/// If [rawQuery] resolves to an existing file, returns its info.
Future<FileSearchFileInfo?> tryResolveExistingPath(String rawQuery) async {
  if (rawQuery.isEmpty) return null;
  final resolved = resolveFilePath(rawQuery);
  final file = File(resolved);
  if (!await file.exists()) return null;
  return FileSearchFileInfo(
    name: p.basename(resolved),
    relativePath: resolved,
    filePath: resolved,
  );
}

/// Searches a single workspace for files matching [query].
Future<List<FileSearchFileInfo>> searchWorkspaceFiles(
  String query,
  ({String name, String path}) workspace, {
  required int maxResults,
}) async {
  final serviceResults = await FileSearchService.instance.searchFiles(
    query: query,
    workspaces: [(name: workspace.name, path: workspace.path)],
  );
  return serviceResults
      .take(maxResults)
      .map(
        (r) => FileSearchFileInfo(
          name: r.fileName,
          relativePath: r.relativePath,
          filePath: r.filePath,
        ),
      )
      .toList();
}
