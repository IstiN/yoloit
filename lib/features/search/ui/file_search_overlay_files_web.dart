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

/// No-op on web: paths are returned unchanged.
String resolveFilePath(String input) => input;

/// Always false on web.
Future<bool> fileExists(String path) async => false;

/// No-op on web: local filesystem search is unavailable.
Future<List<FileSearchFileInfo>> collectMatchingFiles(
  List<String> roots,
  List<String> queries, {
  required int maxResults,
}) async => const [];

/// No-op on web.
Future<FileSearchFileInfo?> tryResolveExistingPath(String rawQuery) async => null;

/// No-op on web: workspace file search is unavailable.
Future<List<FileSearchFileInfo>> searchWorkspaceFiles(
  String query,
  ({String name, String path}) workspace, {
  required int maxResults,
}) async => const [];
