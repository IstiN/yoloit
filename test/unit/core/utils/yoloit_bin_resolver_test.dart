import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/utils/yoloit_bin_resolver.dart';

void main() {
  group('resolveYoloitBin', () {
    test('prefers the installed location when it exists', () {
      final home = Platform.environment['HOME'] ?? '';
      final installed = File('$home/.config/yoloit/yoloit');
      final resolved = resolveYoloitBin();
      if (installed.existsSync()) {
        expect(resolved, installed.path);
      } else {
        // No installed binary: falls back to the tree walk from the current
        // working directory (the repo root during `flutter test`, which has
        // tools/yoloit).
        expect(resolved, isNotNull);
        expect(resolved, endsWith(p.join('tools', 'yoloit')));
      }
    });
  });

  group('searchUpTreeForYoloitBin', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('yoloit_bin_test');
    });

    tearDown(() {
      if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
    });

    Directory makeToolsBin(Directory repo) {
      final tools = Directory(p.join(repo.path, 'tools'))..createSync();
      File(p.join(tools.path, 'yoloit')).writeAsStringSync('#!/bin/sh\n');
      return tools;
    }

    test('finds tools/yoloit at the root itself', () {
      final repo = Directory(p.join(tempDir.path, 'repo'))..createSync();
      makeToolsBin(repo);

      final found = searchUpTreeForYoloitBin([repo]);
      expect(found, p.join(repo.path, 'tools', 'yoloit'));
    });

    test('walks up from a nested directory', () {
      final repo = Directory(p.join(tempDir.path, 'repo'))..createSync();
      makeToolsBin(repo);
      final deep = Directory(p.join(repo.path, 'a', 'b', 'c'))
        ..createSync(recursive: true);

      final found = searchUpTreeForYoloitBin([deep]);
      expect(found, p.join(repo.path, 'tools', 'yoloit'));
    });

    test('honors maxDepth and returns null when the binary is too far up', () {
      final repo = Directory(p.join(tempDir.path, 'repo'))..createSync();
      makeToolsBin(repo);
      final deep = Directory(p.join(repo.path, 'a', 'b'))
        ..createSync(recursive: true);

      // depth 0 → a/b, depth 1 → a: the repo root is never checked.
      expect(searchUpTreeForYoloitBin([deep], maxDepth: 2), isNull);
      expect(searchUpTreeForYoloitBin([deep], maxDepth: 3), isNotNull);
    });

    test('returns null when no ancestor has tools/yoloit', () {
      final plain = Directory(p.join(tempDir.path, 'plain'))..createSync();
      expect(searchUpTreeForYoloitBin([plain], maxDepth: 3), isNull);
    });

    test('skips empty and duplicate roots', () {
      final repo = Directory(p.join(tempDir.path, 'repo'))..createSync();
      makeToolsBin(repo);

      final found = searchUpTreeForYoloitBin([
        Directory(''),
        repo,
        Directory(repo.path),
      ]);
      expect(found, p.join(repo.path, 'tools', 'yoloit'));
    });

    test('tries the next root when the first has no match', () {
      final plain = Directory(p.join(tempDir.path, 'plain'))..createSync();
      final repo = Directory(p.join(tempDir.path, 'other', 'repo'))
        ..createSync(recursive: true);
      makeToolsBin(repo);

      // maxDepth 1 keeps the walk local so only the second root can match.
      final found = searchUpTreeForYoloitBin([plain, repo], maxDepth: 1);
      expect(found, p.join(repo.path, 'tools', 'yoloit'));
    });
  });
}
