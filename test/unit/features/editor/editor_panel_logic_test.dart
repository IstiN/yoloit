/// Unit tests for the pure helpers extracted from file_editor_panel.dart
/// into editor_panel_logic.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/editor/utils/editor_panel_logic.dart';

void main() {
  // ── parseDiffMarkers ──────────────────────────────────────────────────────
  group('parseDiffMarkers', () {
    test('empty diff returns empty map', () {
      expect(parseDiffMarkers(''), isEmpty);
    });

    test('added lines are marked as added', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,3 +1,4 @@
 line1
+newLine
 line2
 line3
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[2], GutterMarkerType.added);
      expect(markers.length, 1);
    });

    test('removed lines mark next line as removed', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,4 +1,3 @@
 line1
-oldLine
 line2
 line3
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[2], GutterMarkerType.removed);
    });

    test('added markers are not overwritten by removed markers', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,2 +1,2 @@
-old
+new
 context
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[1], GutterMarkerType.added);
    });

    test('consecutive removals only mark the next line once', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,4 +1,2 @@
 line1
-gone1
-gone2
 line2
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[2], GutterMarkerType.removed);
      expect(markers.length, 1);
    });

    test('multiple hunks track new-file line numbers', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,2 +1,3 @@
 same
+added1
 same2
@@ -10,2 +11,3 @@
 other
+added2
 end
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[2], GutterMarkerType.added);
      expect(markers[12], GutterMarkerType.added);
    });

    test('hunk header without +N match leaves counter untouched', () {
      const diff = '@@ no-line-info @@\n context\n+added\n';
      final markers = parseDiffMarkers(diff);
      // newLine starts at 0; context bumps to 1, added bumps to 2.
      expect(markers[2], GutterMarkerType.added);
    });

    test('backslash lines do not advance the counter', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -1,1 +1,1 @@
-old
\\ No newline at end of file
+new
\\ No newline at end of file
''';
      final markers = parseDiffMarkers(diff);
      expect(markers[1], GutterMarkerType.added);
    });

    test('file headers ---/+++ are ignored', () {
      const diff = '''
--- a/foo.dart
+++ b/foo.dart
@@ -5,1 +5,1 @@
 ctx
''';
      expect(parseDiffMarkers(diff), isEmpty);
    });
  });

  // ── File type helpers ─────────────────────────────────────────────────────
  group('file type helpers', () {
    test('isMarkdownPath recognizes md/mdx/markdown case-insensitively', () {
      expect(isMarkdownPath('a/b/notes.md'), isTrue);
      expect(isMarkdownPath('doc.MDX'), isTrue);
      expect(isMarkdownPath('README.markdown'), isTrue);
      expect(isMarkdownPath('main.dart'), isFalse);
    });

    test('isEditorImagePath recognizes raster formats', () {
      for (final ext in ['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'ico']) {
        expect(isEditorImagePath('img/pic.$ext'), isTrue, reason: ext);
      }
      expect(isEditorImagePath('img/PIC.PNG'), isTrue);
      expect(isEditorImagePath('img/vector.svg'), isFalse);
      expect(isEditorImagePath('main.dart'), isFalse);
    });

    test('isSvgPath only matches svg', () {
      expect(isSvgPath('assets/logo.svg'), isTrue);
      expect(isSvgPath('assets/logo.SVG'), isTrue);
      expect(isSvgPath('assets/logo.png'), isFalse);
    });
  });

  // ── isLargeEditorFile ─────────────────────────────────────────────────────
  group('isLargeEditorFile', () {
    test('null content is not large', () {
      expect(isLargeEditorFile(null), isFalse);
    });

    test('small content is not large', () {
      expect(isLargeEditorFile('a\nb\nc'), isFalse);
    });

    test('content over the byte threshold is large', () {
      final big = 'x' * (kLargeFileByteThreshold + 1);
      expect(isLargeEditorFile(big), isTrue);
    });

    test('content with more lines than the threshold is large', () {
      final manyLines = List.filled(
        kLargeFileLineThreshold + 2,
        'l',
      ).join('\n');
      expect(isLargeEditorFile(manyLines), isTrue);
    });

    test('content just under both thresholds is not large', () {
      final lines = List.filled(100, 'short').join('\n');
      expect(isLargeEditorFile(lines), isFalse);
    });
  });

  // ── Outline symbol parsing ────────────────────────────────────────────────
  group('parseOutlineSymbols — Dart', () {
    test('finds class, enum, mixin, extension as class symbols', () {
      const src = '''
class MyWidget {}
enum Status { active }
mixin Logging {}
extension StringX on String {}
abstract class BaseRepo {}
''';
      final syms = parseOutlineSymbols(src, 'lib/f.dart');
      final names = syms.where((s) => s.isClass).map((s) => s.name).toList();
      expect(
        names,
        containsAll(['MyWidget', 'Status', 'Logging', 'StringX', 'BaseRepo']),
      );
    });

    test('finds typed function declarations', () {
      const src =
          'void doSomething(String x) {\n}\nFuture<void> load() async {}\n';
      final syms = parseOutlineSymbols(src, 'f.dart');
      expect(syms.any((s) => s.name == 'doSomething()' && !s.isClass), isTrue);
      expect(syms.any((s) => s.name == 'load()'), isTrue);
    });

    test('keywords are not treated as functions', () {
      const src = 'void main() {\n  if (true) {}\n  return;\n}\n';
      final syms = parseOutlineSymbols(src, 'f.dart');
      expect(syms.where((s) => s.name == 'if()'), isEmpty);
      expect(syms.where((s) => s.name == 'return()'), isEmpty);
    });

    test('line numbers are 1-based', () {
      const src = 'class A {}\nclass B {}';
      final syms = parseOutlineSymbols(src, 'f.dart');
      expect(syms.firstWhere((s) => s.name == 'A').line, 1);
      expect(syms.firstWhere((s) => s.name == 'B').line, 2);
    });

    test('empty source returns no symbols', () {
      expect(parseOutlineSymbols('', 'f.dart'), isEmpty);
    });

    test('unknown extension returns no symbols', () {
      expect(parseOutlineSymbols('class A {}', 'f.rb'), isEmpty);
    });
  });

  group('parseOutlineSymbols — JS/TS', () {
    test('finds class', () {
      final syms = parseOutlineSymbols('class UserService {\n}', 'f.ts');
      expect(syms.single.name, 'UserService');
      expect(syms.single.isClass, isTrue);
      expect(syms.single.line, 1);
    });

    test('finds plain/async/exported function declarations', () {
      const src = '''
function fetchUser(id) {}
export async function loadPage() {}
''';
      final syms = parseOutlineSymbols(src, 'f.js');
      final names = syms.map((s) => s.name).toList();
      expect(names, containsAll(['fetchUser()', 'loadPage()']));
    });

    test('finds arrow-function constants', () {
      const src =
          'const handleClick = () => {\n}\nlet load = async (x) => x;\n';
      final syms = parseOutlineSymbols(src, 'f.jsx');
      final names = syms.map((s) => s.name).toList();
      expect(names, contains('handleClick()'));
      expect(names, contains('load()'));
    });

    test('ignores non-symbol lines', () {
      const src = 'const x = 1;\nconsole.log(x);\nimport a from "b";\n';
      expect(parseOutlineSymbols(src, 'f.ts'), isEmpty);
    });
  });

  group('parseOutlineSymbols — Python', () {
    test('finds class and def/async def', () {
      const src = '''
class Animal:
    def speak(self):
        pass
    async def eat(self):
        pass
''';
      final syms = parseOutlineSymbols(src, 'f.py');
      expect(syms.any((s) => s.name == 'Animal' && s.isClass), isTrue);
      expect(syms.any((s) => s.name == 'speak()' && !s.isClass), isTrue);
      expect(syms.any((s) => s.name == 'eat()' && !s.isClass), isTrue);
      expect(syms.firstWhere((s) => s.name == 'speak()').line, 2);
    });

    test('ignores non-class/def lines', () {
      const src = 'x = 1\nprint("hello")\ndefinition = "not a def"\n';
      expect(parseOutlineSymbols(src, 'f.py'), isEmpty);
    });
  });

  group('parseOutlineSymbols — cache', () {
    test('returns identical cached instance on repeat parse', () {
      const src = 'class Cached {}\n';
      final first = parseOutlineSymbols(src, 'cached_path.dart');
      final second = parseOutlineSymbols(src, 'cached_path.dart');
      expect(identical(first, second), isTrue);
    });

    test('same content under different paths is cached separately', () {
      const src = 'class Per {}\n';
      final a = parseOutlineSymbols(src, 'a_path.dart');
      final b = parseOutlineSymbols(src, 'b_path.dart');
      expect(identical(a, b), isFalse);
      expect(a, b);
    });

    test('cache trims beyond 50 entries without throwing', () {
      for (var i = 0; i < 60; i++) {
        parseOutlineSymbols('class C$i {}\n', 'trim_$i.dart');
      }
      final syms = parseOutlineSymbols('class Last {}\n', 'trim_last.dart');
      expect(syms.single.name, 'Last');
    });
  });

  // ── closingBracketFor / applyAutoPair ─────────────────────────────────────
  group('closingBracketFor', () {
    test('open brackets map to closers', () {
      expect(closingBracketFor('('), ')');
      expect(closingBracketFor('['), ']');
      expect(closingBracketFor('{'), '}');
    });

    test('other characters return null', () {
      for (final ch in [')', ']', '}', '"', "'", 'a', ' ', '\n']) {
        expect(closingBracketFor(ch), isNull, reason: 'char: $ch');
      }
    });
  });

  group('applyAutoPair', () {
    test('inserts closing bracket after typing an opener', () {
      final r = applyAutoPair(
        prevText: 'a',
        curText: 'a(',
        selectionCollapsed: true,
        cursorPos: 2,
      );
      expect(r, isNotNull);
      expect(r!.text, 'a()');
      expect(r.cursor, 2);
    });

    test('returns null when selection is not collapsed', () {
      expect(
        applyAutoPair(
          prevText: 'a',
          curText: 'a(',
          selectionCollapsed: false,
          cursorPos: 2,
        ),
        isNull,
      );
    });

    test('returns null when length delta is not exactly one', () {
      expect(
        applyAutoPair(
          prevText: 'a',
          curText: 'a((',
          selectionCollapsed: true,
          cursorPos: 3,
        ),
        isNull,
      );
    });

    test('returns null at the very start of the text', () {
      expect(
        applyAutoPair(
          prevText: '',
          curText: '(',
          selectionCollapsed: true,
          cursorPos: 0,
        ),
        isNull,
      );
    });

    test('returns null for non-bracket characters', () {
      expect(
        applyAutoPair(
          prevText: 'a',
          curText: 'ab',
          selectionCollapsed: true,
          cursorPos: 2,
        ),
        isNull,
      );
    });

    test('does not double-close when the next char is already the closer', () {
      // Typing ( with cursor directly before an existing ).
      expect(
        applyAutoPair(
          prevText: 'a)',
          curText: 'a()',
          selectionCollapsed: true,
          cursorPos: 2,
        ),
        isNull,
      );
    });
  });

  // ── lineRange ─────────────────────────────────────────────────────────────
  group('lineRange', () {
    const text = 'line one\nline two\nline three';

    test('first line starts at 0', () {
      final r = lineRange(text, 0);
      expect((r.start, r.end), (0, 8));
    });

    test('middle line range', () {
      final r = lineRange(text, 10);
      expect(text.substring(r.start, r.end), 'line two');
    });

    test('last line end equals text length', () {
      final r = lineRange(text, 22);
      expect(r.end, text.length);
      expect(text.substring(r.start, r.end), 'line three');
    });

    test('cursor at start of second line', () {
      final r = lineRange(text, 9);
      expect(text.substring(r.start, r.end), 'line two');
    });

    test('single line and empty text', () {
      expect(lineRange('hello', 2), (start: 0, end: 5));
      expect(lineRange('', 0), (start: 0, end: 0));
    });
  });

  // ── toggleCommentLine ─────────────────────────────────────────────────────
  group('toggleCommentLine', () {
    test('comments an uncommented line preserving indent', () {
      final r = toggleCommentLine('  final x = 1;\nfinal y = 2;', 6, '// ');
      expect(r.text, '  // final x = 1;\nfinal y = 2;');
      expect(r.cursor, 6 + 3);
    });

    test('uncomments a commented line', () {
      final r = toggleCommentLine('  // final x = 1;', 6, '// ');
      expect(r.text, '  final x = 1;');
      expect(r.cursor, 6 - 3);
    });

    test('cursor clamps to line start when comment delta exceeds position', () {
      final r = toggleCommentLine('// abc', 1, '// ');
      expect(r.text, 'abc');
      expect(r.cursor, 0);
    });

    test('targets only the cursor line', () {
      final r = toggleCommentLine('one\ntwo\nthree', 5, '# ');
      expect(r.text, 'one\n# two\nthree');
    });
  });

  // ── duplicateLineInText ───────────────────────────────────────────────────
  group('duplicateLineInText', () {
    test('duplicates the cursor line below keeping column', () {
      final r = duplicateLineInText('one\ntwo', 5);
      expect(r.text, 'one\ntwo\ntwo');
      expect(r.cursor, 5 + 4); // same column on the new copy
    });

    test('duplicates the last line', () {
      final r = duplicateLineInText('one\ntwo', 1);
      expect(r.text, 'one\none\ntwo');
    });
  });

  // ── deleteLineInText ──────────────────────────────────────────────────────
  group('deleteLineInText', () {
    test('deletes a middle line and moves cursor to line start', () {
      final r = deleteLineInText('one\ntwo\nthree', 5);
      expect(r!.text, 'one\nthree');
      expect(r.cursor, 4);
    });

    test('deletes the last line including the preceding newline', () {
      final r = deleteLineInText('one\ntwo', 5);
      expect(r!.text, 'one');
      expect(r.cursor, 3);
    });

    test('deletes the first line', () {
      final r = deleteLineInText('one\ntwo', 1);
      expect(r!.text, 'two');
      expect(r.cursor, 0);
    });

    test('returns null for a single-line text', () {
      expect(deleteLineInText('only', 2), isNull);
    });
  });

  // ── moveLineUpInText / moveLineDownInText ─────────────────────────────────
  group('moveLineUpInText', () {
    test('swaps with the line above keeping column', () {
      final r = moveLineUpInText('one\ntwo\nthree', 5);
      expect(r!.text, 'two\none\nthree');
      expect(r.cursor, 1);
    });

    test('returns null on the first line', () {
      expect(moveLineUpInText('one\ntwo', 1), isNull);
    });

    test('moves the last line up', () {
      final r = moveLineUpInText('one\ntwo', 5);
      expect(r!.text, 'two\none');
    });
  });

  group('moveLineDownInText', () {
    test('swaps with the line below keeping column', () {
      final r = moveLineDownInText('one\ntwo\nthree', 1);
      expect(r!.text, 'two\none\nthree');
      expect(r.cursor, 4 + 1);
    });

    test('returns null on the last line', () {
      expect(moveLineDownInText('one\ntwo', 5), isNull);
    });
  });

  // ── indentLineInText / outdentLineInText ──────────────────────────────────
  group('indentLineInText', () {
    test('adds two spaces at line start and shifts cursor', () {
      final r = indentLineInText('one\ntwo', 5);
      expect(r.text, 'one\n  two');
      expect(r.cursor, 7);
    });
  });

  group('outdentLineInText', () {
    test('removes two leading spaces', () {
      final r = outdentLineInText('  abc', 4);
      expect(r!.text, 'abc');
      expect(r.cursor, 2);
    });

    test('removes a single leading space', () {
      final r = outdentLineInText(' abc', 3);
      expect(r!.text, 'abc');
      expect(r.cursor, 2);
    });

    test('cursor clamps to line start', () {
      final r = outdentLineInText('  abc', 1);
      expect(r!.cursor, 0);
    });

    test('returns null when no leading whitespace', () {
      expect(outdentLineInText('abc', 1), isNull);
    });
  });

  // ── computeQuickFindMatches ───────────────────────────────────────────────
  group('computeQuickFindMatches', () {
    test('empty query yields no offsets', () {
      final r = computeQuickFindMatches(
        text: 'hello hello',
        query: '',
        searchOrigin: 0,
      );
      expect(r.offsets, isEmpty);
      expect(r.current, 0);
    });

    test('finds all case-insensitive occurrences', () {
      final r = computeQuickFindMatches(
        text: 'Vo vortex VO',
        query: 'vo',
        searchOrigin: 0,
      );
      expect(r.offsets, [0, 3, 10]);
    });

    test('picks the first match at or after the search origin', () {
      final r = computeQuickFindMatches(
        text: 'ab ab ab',
        query: 'ab',
        searchOrigin: 4,
      );
      expect(r.offsets, [0, 3, 6]);
      expect(r.current, 2);
    });

    test('wraps to the first match when origin is past all matches', () {
      final r = computeQuickFindMatches(
        text: 'ab xx ab',
        query: 'ab',
        searchOrigin: 7,
      );
      expect(r.current, 0); // 6 < 7 → no match at/after origin → wraps
    });

    test('origin exactly on a match selects that match', () {
      final r = computeQuickFindMatches(
        text: 'ab xx ab',
        query: 'ab',
        searchOrigin: 6,
      );
      expect(r.current, 1);
    });

    test('no matches yields empty offsets', () {
      final r = computeQuickFindMatches(
        text: 'nothing here',
        query: 'zzz',
        searchOrigin: 0,
      );
      expect(r.offsets, isEmpty);
      expect(r.current, 0);
    });
  });

  // ── Character filtering ───────────────────────────────────────────────────
  group('isPrintableTypeaheadCharacter', () {
    test('accepts regular characters', () {
      expect(isPrintableTypeaheadCharacter('a'), isTrue);
      expect(isPrintableTypeaheadCharacter(' '), isTrue);
      expect(isPrintableTypeaheadCharacter('é'), isTrue);
    });

    test('rejects null and empty', () {
      expect(isPrintableTypeaheadCharacter(null), isFalse);
      expect(isPrintableTypeaheadCharacter(''), isFalse);
    });

    test('rejects control characters', () {
      expect(isPrintableTypeaheadCharacter('\n'), isFalse);
      expect(isPrintableTypeaheadCharacter('\t'), isFalse);
      expect(isPrintableTypeaheadCharacter('\x1B'), isFalse);
    });
  });

  group('shouldAcceptQuickFindCharacter', () {
    test('accepts printable character without modifiers', () {
      expect(
        shouldAcceptQuickFindCharacter(modifierPressed: false, character: 'v'),
        isTrue,
      );
    });

    test('rejects when a modifier is pressed', () {
      expect(
        shouldAcceptQuickFindCharacter(modifierPressed: true, character: 'v'),
        isFalse,
      );
    });

    test('rejects control characters', () {
      expect(
        shouldAcceptQuickFindCharacter(modifierPressed: false, character: '\n'),
        isFalse,
      );
      expect(
        shouldAcceptQuickFindCharacter(modifierPressed: false, character: null),
        isFalse,
      );
    });
  });

  group('shouldIgnoreTypeahead', () {
    test('ignores when search bar is hidden', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: false,
          patternFocused: false,
          isKeyDownOrRepeat: true,
          modifierPressed: false,
          character: 'a',
        ),
        isTrue,
      );
    });

    test('ignores when the pattern field already has focus', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: true,
          isKeyDownOrRepeat: true,
          modifierPressed: false,
          character: 'a',
        ),
        isTrue,
      );
    });

    test('ignores key-up events', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: false,
          isKeyDownOrRepeat: false,
          modifierPressed: false,
          character: 'a',
        ),
        isTrue,
      );
    });

    test('ignores when a modifier is pressed', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: false,
          isKeyDownOrRepeat: true,
          modifierPressed: true,
          character: 'a',
        ),
        isTrue,
      );
    });

    test('ignores control characters', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: false,
          isKeyDownOrRepeat: true,
          modifierPressed: false,
          character: '\x07',
        ),
        isTrue,
      );
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: false,
          isKeyDownOrRepeat: true,
          modifierPressed: false,
          character: null,
        ),
        isTrue,
      );
    });

    test('accepts a plain printable keypress', () {
      expect(
        shouldIgnoreTypeahead(
          searchVisible: true,
          patternFocused: false,
          isKeyDownOrRepeat: true,
          modifierPressed: false,
          character: 'x',
        ),
        isFalse,
      );
    });
  });

  // ── lineStartOffset ───────────────────────────────────────────────────────
  group('lineStartOffset', () {
    const text = 'one\ntwo\nthree';

    test('line 1 starts at 0', () {
      expect(lineStartOffset(text, 1), 0);
    });

    test('computes start of later lines', () {
      expect(lineStartOffset(text, 2), 4);
      expect(lineStartOffset(text, 3), 8);
    });

    test('clamps to text length beyond the last line', () {
      expect(lineStartOffset(text, 99), text.length);
    });
  });
}
