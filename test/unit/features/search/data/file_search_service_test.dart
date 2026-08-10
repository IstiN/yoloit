import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/search/data/file_search_service.dart';

void main() {
  group('SearchResult', () {
    test('relativePath computes path relative to workspace', () {
      const result = SearchResult(
        filePath: '/home/user/project/lib/main.dart',
        workspaceName: 'project',
        workspacePath: '/home/user/project',
      );
      expect(result.relativePath, 'lib/main.dart');
    });

    test('fileName returns basename', () {
      const result = SearchResult(
        filePath: '/home/user/project/lib/main.dart',
        workspaceName: 'project',
        workspacePath: '/home/user/project',
      );
      expect(result.fileName, 'main.dart');
    });
  });

  group('FileSearchService.searchFiles', () {
    test('returns empty list for empty query', () async {
      final results = await FileSearchService.instance.searchFiles(
        query: '',
        workspaces: [(name: 'test', path: '/tmp')],
      );
      expect(results, isEmpty);
    });

    test('finds matching files by name', () async {
      final tmpDir = Directory.systemTemp.createTempSync('file_search_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/main.dart').createSync();
      File('${tmpDir.path}/README.md').createSync();
      File('${tmpDir.path}/test.dart').createSync();

      final results = await FileSearchService.instance.searchFiles(
        query: 'main',
        workspaces: [(name: 'test', path: tmpDir.path)],
      );

      expect(results.any((r) => r.fileName == 'main.dart'), isTrue);
      expect(results.any((r) => r.fileName == 'README.md'), isFalse);
    });

    test('ignores dot directories', () async {
      final tmpDir = Directory.systemTemp.createTempSync('file_search_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/visible.dart').createSync();
      Directory('${tmpDir.path}/.git').createSync();
      File('${tmpDir.path}/.git/config').createSync(recursive: true);

      final results = await FileSearchService.instance.searchFiles(
        query: 'config',
        workspaces: [(name: 'test', path: tmpDir.path)],
      );

      expect(results, isEmpty);
    });

    test('respects maxResults across workspaces', () async {
      final tmpDir = Directory.systemTemp.createTempSync('file_search_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      for (var i = 0; i < 55; i++) {
        File('${tmpDir.path}/file_${i.toString().padLeft(2, '0')}.dart').createSync();
      }

      final results = await FileSearchService.instance.searchFiles(
        query: 'file',
        workspaces: [(name: 'test', path: tmpDir.path)],
      );

      expect(results.length, lessThanOrEqualTo(50));
    });

    test('returns empty list for non-existent workspace', () async {
      final results = await FileSearchService.instance.searchFiles(
        query: 'test',
        workspaces: [(name: 'missing', path: '/nonexistent/path/12345')],
      );
      expect(results, isEmpty);
    });
  });

  group('FileSearchService.searchContent', () {
    test('returns empty list for empty query', () async {
      final results = await FileSearchService.instance.searchContent(
        query: '',
        workspaces: [(name: 'test', path: '/tmp')],
      );
      expect(results, isEmpty);
    });

    test('finds files containing query', () async {
      final tmpDir = Directory.systemTemp.createTempSync('file_search_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/hello.txt').writeAsStringSync('hello world');
      File('${tmpDir.path}/goodbye.txt').writeAsStringSync('goodbye world');

      final results = await FileSearchService.instance.searchContent(
        query: 'hello',
        workspaces: [(name: 'test', path: tmpDir.path)],
      );

      expect(results.any((r) => r.fileName == 'hello.txt'), isTrue);
      expect(results.any((r) => r.fileName == 'goodbye.txt'), isFalse);
      final match = results.firstWhere((r) => r.fileName == 'hello.txt');
      expect(match.lineNumber, isNotNull);
      expect(match.lineContent, contains('hello'));
    });

    test('respects maxResults', () async {
      final tmpDir = Directory.systemTemp.createTempSync('file_search_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      for (var i = 0; i < 30; i++) {
        File('${tmpDir.path}/file_$i.txt').writeAsStringSync('common keyword');
      }

      final results = await FileSearchService.instance.searchContent(
        query: 'common',
        workspaces: [(name: 'test', path: tmpDir.path)],
      );

      expect(results.length, lessThanOrEqualTo(50));
    });

    test('returns empty list for non-existent workspace', () async {
      final results = await FileSearchService.instance.searchContent(
        query: 'test',
        workspaces: [(name: 'missing', path: '/nonexistent/path/12345')],
      );
      expect(results, isEmpty);
    });
  });

  group('FileSearchService._grepFallback', () {
    test('finds matching files with line numbers via grep', () async {
      final tmpDir = Directory.systemTemp.createTempSync('grep_fallback_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/alpha.txt')
          .writeAsStringSync('nothing here\nneedle in a haystack\n');
      File('${tmpDir.path}/beta.txt').writeAsStringSync('no match here\n');

      final results = await FileSearchService.instance.grepFallbackForTest(
        tmpDir.path,
        'ws',
        'needle',
      );

      expect(results, hasLength(1));
      final match = results.single;
      expect(match.fileName, 'alpha.txt');
      expect(match.workspaceName, 'ws');
      expect(match.lineNumber, 2);
      expect(match.lineContent, contains('needle'));
    });

    test('skips ignored directories', () async {
      final tmpDir = Directory.systemTemp.createTempSync('grep_fallback_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      Directory('${tmpDir.path}/node_modules').createSync();
      File('${tmpDir.path}/node_modules/dep.js')
          .writeAsStringSync('needle\n');

      final results = await FileSearchService.instance.grepFallbackForTest(
        tmpDir.path,
        'ws',
        'needle',
      );

      expect(results, isEmpty);
    });

    test('returns empty list when nothing matches (grep exit 1)', () async {
      final tmpDir = Directory.systemTemp.createTempSync('grep_fallback_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/file.txt').writeAsStringSync('content\n');

      final results = await FileSearchService.instance.grepFallbackForTest(
        tmpDir.path,
        'ws',
        'absent-pattern',
      );

      expect(results, isEmpty);
    });

    test('returns empty list for an invalid regex (grep exit 2)', () async {
      final tmpDir = Directory.systemTemp.createTempSync('grep_fallback_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/file.txt').writeAsStringSync('content\n');

      final results = await FileSearchService.instance.grepFallbackForTest(
        tmpDir.path,
        'ws',
        '[unclosed',
      );

      expect(results, isEmpty);
    });

    test('returns empty list for a missing directory', () async {
      final results = await FileSearchService.instance.grepFallbackForTest(
        '/nonexistent/path/12345',
        'ws',
        'needle',
      );

      expect(results, isEmpty);
    });

    test('truncates long matching lines to 80 characters', () async {
      final tmpDir = Directory.systemTemp.createTempSync('grep_fallback_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      final longLine = 'needle${'x' * 200}';
      File('${tmpDir.path}/long.txt').writeAsStringSync('$longLine\n');

      final results = await FileSearchService.instance.grepFallbackForTest(
        tmpDir.path,
        'ws',
        'needle',
      );

      expect(results, hasLength(1));
      expect(results.single.lineContent!.length, 80);
    });
  });
}
