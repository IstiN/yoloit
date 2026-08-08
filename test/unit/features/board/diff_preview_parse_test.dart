import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/diff_preview_plugin_vm.dart';

void main() {
  group('parseDiffPreviewLines', () {
    test('parses hunk header with counts and tracks line numbers', () {
      final lines = parseDiffPreviewLines(
        '@@ -1,3 +1,4 @@ void main() {\n'
        ' context\n'
        '-old line\n'
        '+new line\n'
        '+another\n',
      );
      expect(lines, hasLength(5));
      expect(lines[0].type, DiffLineType.hunk);
      expect(lines[0].content, '@@ -1,3 +1,4 @@ void main() {');
      expect(lines[1].type, DiffLineType.context);
      expect(lines[1].oldLineNo, 1);
      expect(lines[1].newLineNo, 1);
      expect(lines[2].type, DiffLineType.removed);
      expect(lines[2].content, 'old line');
      expect(lines[2].oldLineNo, 2);
      expect(lines[2].newLineNo, isNull);
      expect(lines[3].type, DiffLineType.added);
      expect(lines[3].content, 'new line');
      expect(lines[3].newLineNo, 2);
      expect(lines[4].newLineNo, 3);
    });

    test('parses hunk header without counts', () {
      final lines = parseDiffPreviewLines('@@ -5 +7 @@\n+x\n');
      expect(lines[0].type, DiffLineType.hunk);
      expect(lines[1].type, DiffLineType.added);
      expect(lines[1].newLineNo, 7);
    });

    test('keeps hunk line when the header does not match the pattern', () {
      final lines = parseDiffPreviewLines('@@ malformed hunk @@\n ctx\n');
      expect(lines[0].type, DiffLineType.hunk);
      expect(lines[0].content, '@@ malformed hunk @@');
      // Line numbers stay at their initial values when the header fails.
      expect(lines[1].type, DiffLineType.context);
      expect(lines[1].oldLineNo, 0);
      expect(lines[1].newLineNo, 0);
    });

    test('skips diff header lines', () {
      final lines = parseDiffPreviewLines(
        'diff --git a/a.txt b/a.txt\n'
        'index 123..456 100644\n'
        '--- a/a.txt\n'
        '+++ b/a.txt\n'
        '@@ -1 +1 @@\n'
        '+hello\n',
      );
      expect(lines, hasLength(2));
      expect(lines[0].type, DiffLineType.hunk);
      expect(lines[1].type, DiffLineType.added);
      expect(lines[1].content, 'hello');
    });

    test('handles multiple hunks resetting line numbers', () {
      final lines = parseDiffPreviewLines(
        '@@ -1 +1 @@\n'
        ' a\n'
        '@@ -10 +12 @@\n'
        '-b\n'
        '+c\n',
      );
      expect(lines, hasLength(5));
      expect(lines[3].type, DiffLineType.removed);
      expect(lines[3].oldLineNo, 10);
      expect(lines[4].type, DiffLineType.added);
      expect(lines[4].newLineNo, 12);
    });

    test('ignores lines without a diff prefix', () {
      final lines = parseDiffPreviewLines(
        'random garbage\n'
        '\\ No newline at end of file\n'
        '@@ -1 +1 @@\n'
        '+x\n',
      );
      expect(lines, hasLength(2));
    });

    test('returns empty list for empty diff', () {
      expect(parseDiffPreviewLines(''), isEmpty);
    });

    test('increments context lines on both sides', () {
      final lines = parseDiffPreviewLines('@@ -3 +4 @@\n one\n two\n-three\n');
      expect(lines[1].oldLineNo, 3);
      expect(lines[1].newLineNo, 4);
      expect(lines[2].oldLineNo, 4);
      expect(lines[2].newLineNo, 5);
      expect(lines[3].oldLineNo, 5);
    });
  });
}
