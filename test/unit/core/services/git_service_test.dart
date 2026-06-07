import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/services/git_service.dart';

void main() {
  group('GitService.parseShortstatForTest', () {
    const service = GitService.instance;

    test('returns zero for empty string', () {
      final result = service.parseShortstatForTest('');
      expect(result.added, 0);
      expect(result.removed, 0);
    });

    test('parses insertions only', () {
      final result = service.parseShortstatForTest(' 5 insertions(+)');
      expect(result.added, 5);
      expect(result.removed, 0);
    });

    test('parses deletions only', () {
      final result = service.parseShortstatForTest(' 3 deletions(-)');
      expect(result.added, 0);
      expect(result.removed, 3);
    });

    test('parses both insertions and deletions', () {
      final result = service.parseShortstatForTest(
        ' 10 files changed, 42 insertions(+), 7 deletions(-)',
      );
      expect(result.added, 42);
      expect(result.removed, 7);
    });

    test('parses large numbers', () {
      final result = service.parseShortstatForTest(
        ' 1000 insertions(+), 500 deletions(-)',
      );
      expect(result.added, 1000);
      expect(result.removed, 500);
    });
  });

  group('GitService.parseStatusForTest', () {
    const service = GitService.instance;

    test('returns empty list for empty string', () {
      final result = service.parseStatusForTest('');
      expect(result, isEmpty);
    });

    test('parses modified file', () {
      final result = service.parseStatusForTest(' M lib/main.dart');
      expect(result.length, 1);
      expect(result[0].path, 'lib/main.dart');
      expect(result[0].indexStatus, ' ');
      expect(result[0].workingTreeStatus, 'M');
    });

    test('parses staged added file', () {
      final result = service.parseStatusForTest('A  new_file.dart');
      expect(result.length, 1);
      expect(result[0].path, 'new_file.dart');
      expect(result[0].indexStatus, 'A');
      expect(result[0].workingTreeStatus, ' ');
      expect(result[0].isAdded, isTrue);
    });

    test('parses deleted file', () {
      final result = service.parseStatusForTest('D  deleted.dart');
      expect(result.length, 1);
      expect(result[0].path, 'deleted.dart');
      expect(result[0].isDeleted, isTrue);
    });

    test('parses untracked file', () {
      final result = service.parseStatusForTest('?? untracked.dart');
      expect(result.length, 1);
      expect(result[0].path, 'untracked.dart');
      expect(result[0].indexStatus, '?');
      expect(result[0].workingTreeStatus, '?');
      expect(result[0].isAdded, isTrue);
    });

    test('parses multiple files', () {
      final result = service.parseStatusForTest(
        ' M lib/main.dart\nA  new.dart\n?? other.dart',
      );
      expect(result.length, 3);
      expect(result[0].path, 'lib/main.dart');
      expect(result[1].path, 'new.dart');
      expect(result[2].path, 'other.dart');
    });

    test('skips lines shorter than 3 chars', () {
      final result = service.parseStatusForTest(' M\nA ');
      expect(result, isEmpty);
    });

    test('isModified detects M status', () {
      final result = service.parseStatusForTest(' M file.dart');
      expect(result[0].isModified, isTrue);
    });

    test('isStaged detects staged changes', () {
      final result = service.parseStatusForTest('M  file.dart');
      expect(result[0].isStaged, isTrue);
    });

    test('isStaged is false for untracked', () {
      final result = service.parseStatusForTest('?? file.dart');
      expect(result[0].isStaged, isFalse);
    });
  });
}
