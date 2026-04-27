import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/search/utils/fuzzy_matcher.dart';

enum SearchMode { files, content }

class SearchResult {
  const SearchResult({
    required this.filePath,
    required this.workspaceName,
    required this.workspacePath,
    this.lineNumber,
    this.lineContent,
  });

  final String filePath;
  final String workspaceName;
  final String workspacePath;
  final int? lineNumber;
  final String? lineContent;

  String get relativePath => p.relative(filePath, from: workspacePath);
  String get fileName => p.basename(filePath);
}

class FileSearchService {
  FileSearchService._();
  static final instance = FileSearchService._();

  static const _maxResults = 50;

  static const _ignoreDirs = {
    '.git', '.dart_tool', 'build', 'node_modules',
    '.idea', '.vscode', '__pycache__', '.gradle',
  };

  /// Cached ripgrep binary path, or null if not available.
  static String? _rgBin;
  static bool _rgChecked = false;

  /// Returns the ripgrep (`rg`) binary if available, null otherwise.
  static Future<String?> _findRg() async {
    if (_rgChecked) return _rgBin;
    _rgChecked = true;

    if (Platform.isWindows) {
      // On Windows use where.exe to find rg in PATH.
      // Install via: winget install BurntSushi.ripgrep.MSVC
      try {
        final result = await Process.run('where', ['rg'], runInShell: true);
        if (result.exitCode == 0) {
          final p = (result.stdout as String).trim().split('\n').first.trim();
          if (p.isNotEmpty) {
            _rgBin = p;
            return _rgBin;
          }
        }
      } catch (_) {}
      return null;
    }

    for (final candidate in ['/opt/homebrew/bin/rg', '/usr/local/bin/rg', '/usr/bin/rg']) {
      if (await File(candidate).exists()) {
        _rgBin = candidate;
        return _rgBin;
      }
    }
    try {
      final result = await Process.run('which', ['rg']);
      if (result.exitCode == 0) {
        final p = (result.stdout as String).trim();
        if (p.isNotEmpty) {
          _rgBin = p;
          return _rgBin;
        }
      }
    } catch (_) {}
    return null;
  }

  /// Search file names matching [query] in [workspaces] using fuzzy matching.
  ///
  /// Supports:
  ///   - Subsequence matching: "PR" matches "PropertyReader"
  ///   - Russian keyboard transliteration: "ЗкщзукенКуфвук" → "PropertyReader"
  Future<List<SearchResult>> searchFiles({
    required String query,
    required List<({String name, String path})> workspaces,
  }) async {
    if (query.isEmpty) return [];

    final results = <SearchResult>[];
    for (final ws in workspaces) {
      if (results.length >= _maxResults) break;
      final wsResults = await _findFiles(ws.path, ws.name, query);
      results.addAll(wsResults.take(_maxResults - results.length));
    }
    return results;
  }

  /// Search file contents matching [query] in [workspacePaths].
  Future<List<SearchResult>> searchContent({
    required String query,
    required List<({String name, String path})> workspaces,
  }) async {
    if (query.isEmpty) return [];

    final results = <SearchResult>[];
    for (final ws in workspaces) {
      if (results.length >= _maxResults) break;
      final wsResults = await _grepContent(ws.path, ws.name, query);
      results.addAll(wsResults.take(_maxResults - results.length));
    }
    return results;
  }

  Future<List<SearchResult>> _findFiles(
    String dirPath,
    String wsName,
    String query,
  ) async {
    try {
      final queries = FuzzyMatcher.candidates(query);
      final scored = <({SearchResult result, int score})>[];

      await _walkDirectory(Directory(dirPath), (file) {
        final name = p.basename(file.path);
        final s = FuzzyMatcher.bestScore(name, queries);
        if (s != null) {
          scored.add((
            result: SearchResult(
              filePath: file.path,
              workspaceName: wsName,
              workspacePath: dirPath,
            ),
            score: s,
          ));
        }
      });

      scored.sort((a, b) => b.score.compareTo(a.score));
      return scored.take(_maxResults).map((e) => e.result).toList();
    } catch (_) {
      return [];
    }
  }

  /// Recursively visits all files under [dir], skipping ignored directories.
  Future<void> _walkDirectory(Directory dir, void Function(File) onFile) async {
    try {
      await for (final entity in dir.list()) {
        if (entity is Directory) {
          if (!_ignoreDirs.contains(p.basename(entity.path))) {
            await _walkDirectory(entity, onFile);
          }
        } else if (entity is File) {
          onFile(entity);
        }
      }
    } catch (_) {
      // Skip unreadable directories
    }
  }

  Future<List<SearchResult>> _grepContent(
    String dirPath,
    String wsName,
    String query,
  ) async {
    try {
      final rg = await _findRg();
      if (rg != null) {
        return _rgContent(rg, dirPath, wsName, query);
      }
      return _grepFallback(dirPath, wsName, query);
    } catch (_) {
      return [];
    }
  }

  Future<List<SearchResult>> _rgContent(
    String rgBin,
    String dirPath,
    String wsName,
    String query,
  ) async {
    final excludeArgs = _ignoreDirs
        .expand((d) => ['--glob=!$d/**'])
        .toList();

    final result = await Process.run(rgBin, [
      '--files-with-matches',
      '--line-number',
      '--max-count=1',
      '--no-heading',
      '-m', '1',
      ...excludeArgs,
      query,
      dirPath,
    ]);

    if (result.exitCode > 1) return [];

    final files = (result.stdout as String)
        .split('\n')
        .where((l) => l.isNotEmpty)
        .take(20)
        .toList();

    final results = <SearchResult>[];
    for (final file in files) {
      if (results.length >= _maxResults) break;
      final lineResult = await Process.run(rgBin, [
        '--line-number',
        '-m', '1',
        query,
        file,
      ]);
      if (lineResult.exitCode == 0) {
        final match = (lineResult.stdout as String).trim();
        final colonIdx = match.indexOf(':');
        if (colonIdx > 0) {
          final lineNum = int.tryParse(match.substring(0, colonIdx));
          final content = match.substring(colonIdx + 1).trim();
          results.add(SearchResult(
            filePath: file,
            workspaceName: wsName,
            workspacePath: dirPath,
            lineNumber: lineNum,
            lineContent: content.length > 80 ? content.substring(0, 80) : content,
          ));
        }
      }
    }
    return results;
  }

  Future<List<SearchResult>> _grepFallback(
    String dirPath,
    String wsName,
    String query,
  ) async {
    if (Platform.isWindows) {
      // grep is not available natively on Windows.
      // Install ripgrep via: winget install BurntSushi.ripgrep.MSVC
      return [];
    }
    try {
      final excludeArgs = _ignoreDirs
          .expand((d) => ['--exclude-dir=$d'])
          .toList();

      final result = await Process.run('grep', [
        '-rn',
        '--include=*',
        '-l',
        '--max-count=1',
        ...excludeArgs,
        query,
        dirPath,
      ]);

      // Now get line numbers for top matches
      if (result.exitCode > 1) return [];

      final files = (result.stdout as String)
          .split('\n')
          .where((l) => l.isNotEmpty)
          .take(20)
          .toList();

      final results = <SearchResult>[];
      for (final file in files) {
        if (results.length >= _maxResults) break;
        final lineResult = await Process.run('grep', [
          '-n',
          '-m', '1',
          ...excludeArgs,
          query,
          file,
        ]);
        if (lineResult.exitCode == 0) {
          final match = (lineResult.stdout as String).trim();
          final colonIdx = match.indexOf(':');
          if (colonIdx > 0) {
            final lineNum = int.tryParse(match.substring(0, colonIdx));
            final content = match.substring(colonIdx + 1).trim();
            results.add(SearchResult(
              filePath: file,
              workspaceName: wsName,
              workspacePath: dirPath,
              lineNumber: lineNum,
              lineContent: content.length > 80 ? content.substring(0, 80) : content,
            ));
          }
        }
      }
      return results;
    } catch (_) {
      return [];
    }
  }
}
