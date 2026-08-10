import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/review/data/diff_service.dart';
import 'package:yoloit/features/review/models/review_models.dart';

void main() {
  const service = DiffService.instance;

  group('DiffService.parseDiff', () {
    test('returns empty list for empty input', () {
      expect(service.parseDiff(''), isEmpty);
    });

    test('parses a single hunk correctly', () {
      const rawDiff = '''
@@ -1,4 +1,5 @@
 context line 1
-removed line
+added line
+another added line
 context line 2
''';
      final hunks = service.parseDiff(rawDiff);
      expect(hunks, hasLength(1));

      final hunk = hunks.first;
      expect(hunk.oldStart, 1);
      expect(hunk.newStart, 1);

      final lines = hunk.lines.where((l) => l.type != DiffLineType.header).toList();
      expect(lines.where((l) => l.type == DiffLineType.context), hasLength(2));
      expect(lines.where((l) => l.type == DiffLineType.remove), hasLength(1));
      expect(lines.where((l) => l.type == DiffLineType.add), hasLength(2));
    });

    test('captures correct line content', () {
      const rawDiff = '''
@@ -10,3 +10,3 @@
-old code
+new code
 unchanged
''';
      final hunks = service.parseDiff(rawDiff);
      final lines = hunks.first.lines.where((l) => l.type != DiffLineType.header).toList();

      final removed = lines.firstWhere((l) => l.type == DiffLineType.remove);
      final added = lines.firstWhere((l) => l.type == DiffLineType.add);
      final context = lines.firstWhere((l) => l.type == DiffLineType.context);

      expect(removed.content, 'old code');
      expect(added.content, 'new code');
      expect(context.content, 'unchanged');
    });

    test('assigns line numbers correctly', () {
      const rawDiff = '''
@@ -5,3 +5,4 @@
 ctx
-removed
+added1
+added2
 ctx2
''';
      final hunks = service.parseDiff(rawDiff);
      final lines = hunks.first.lines.where((l) => l.type != DiffLineType.header).toList();

      // Context line at old=5, new=5
      expect(lines[0].oldLineNum, 5);
      expect(lines[0].newLineNum, 5);

      // Removed line at old=6, no new
      expect(lines[1].oldLineNum, 6);
      expect(lines[1].newLineNum, isNull);

      // Added lines: no old, new=6 and new=7
      expect(lines[2].oldLineNum, isNull);
      expect(lines[2].newLineNum, 6);
      expect(lines[3].oldLineNum, isNull);
      expect(lines[3].newLineNum, 7);
    });

    test('parses multiple hunks', () {
      const rawDiff = '''
@@ -1,2 +1,2 @@
-a
+b
@@ -10,2 +10,2 @@
-c
+d
''';
      final hunks = service.parseDiff(rawDiff);
      expect(hunks, hasLength(2));
      expect(hunks[0].oldStart, 1);
      expect(hunks[1].oldStart, 10);
    });

    test('ignores diff file header lines (--- and +++)', () {
      const rawDiff = '''
--- a/file.dart
+++ b/file.dart
@@ -1,2 +1,2 @@
-old
+new
''';
      final hunks = service.parseDiff(rawDiff);
      expect(hunks, hasLength(1));
      final lines = hunks.first.lines.where((l) => l.type != DiffLineType.header).toList();
      expect(lines, hasLength(2));
    });

    test('hunk header is preserved verbatim', () {
      const rawDiff = '@@ -42,6 +42,7 @@ class Foo {\n context\n';
      final hunks = service.parseDiff(rawDiff);
      expect(hunks.first.header, contains('@@ -42,6 +42,7 @@'));
    });
  });

  group('DiffService.getChangedFiles', () {
    late Directory repo;

    Future<void> git(List<String> args) async {
      final result = await Process.run(
        'git',
        ['-c', 'user.email=test@example.com', '-c', 'user.name=Test', ...args],
        workingDirectory: repo.path,
      );
      expect(result.exitCode, 0, reason: 'git ${args.join(' ')}: ${result.stderr}');
    }

    setUp(() async {
      repo = Directory.systemTemp.createTempSync('diff_service_test_');
      await git(['init']);
      File('${repo.path}/committed.txt').writeAsStringSync('base\n');
      File('${repo.path}/deleted.txt').writeAsStringSync('gone\n');
      File('${repo.path}/renamed_old.txt').writeAsStringSync('rename me\n');
      await git(['add', '.']);
      await git(['commit', '-m', 'init']);
    });

    tearDown(() {
      if (repo.existsSync()) repo.deleteSync(recursive: true);
    });

    test('maps porcelain statuses to file change statuses', () async {
      // Working tree modifications covering every status branch.
      File('${repo.path}/committed.txt').writeAsStringSync('changed\n');
      File('${repo.path}/deleted.txt').deleteSync();
      await git(['mv', 'renamed_old.txt', 'renamed_new.txt']);
      File('${repo.path}/staged.txt').writeAsStringSync('staged\n');
      await git(['add', 'staged.txt']);
      File('${repo.path}/untracked.txt').writeAsStringSync('untracked\n');

      final changes = await service.getChangedFiles(repo.path);
      final byPath = {for (final c in changes) c.path: c};

      expect(byPath['committed.txt']!.status, FileChangeStatus.modified);
      expect(byPath['committed.txt']!.isStaged, isFalse);
      expect(byPath['committed.txt']!.repoPath, repo.path);

      expect(byPath['deleted.txt']!.status, FileChangeStatus.deleted);

      expect(byPath['staged.txt']!.status, FileChangeStatus.added);
      expect(byPath['staged.txt']!.isStaged, isTrue);

      final renamed = byPath.values.singleWhere(
        (c) => c.path.contains('renamed_new.txt'),
      );
      expect(renamed.status, FileChangeStatus.renamed);

      expect(byPath['untracked.txt']!.status, FileChangeStatus.untracked);
    });

    test('returns empty list for a clean repository', () async {
      final changes = await service.getChangedFiles(repo.path);
      expect(changes, isEmpty);
    });

    test('returns empty list for a path that is not a git repo', () async {
      final plain = Directory.systemTemp.createTempSync('diff_service_plain_');
      addTearDown(() => plain.deleteSync(recursive: true));

      final changes = await service.getChangedFiles(plain.path);
      expect(changes, isEmpty);
    });
  });
}
