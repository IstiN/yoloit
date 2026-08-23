import 'package:flutter_test/flutter_test.dart';
import 'package:yoxterm/src/core/buffer/line.dart' as xterm_buffer;
import 'package:yoxterm/src/core/cursor.dart' as xterm_cursor;
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

xterm_buffer.BufferLine _lineWith(String text) {
  final line = xterm_buffer.BufferLine(text.length);
  for (var i = 0; i < text.length; i++) {
    // Fresh CursorStyle per cell: CursorStyle.empty is a shared mutable
    // instance, and mutating it would leak attributes across tests.
    line.setCell(i, text.codeUnitAt(i), 1, xterm_cursor.CursorStyle());
  }
  return line;
}

void main() {
  group('terminalRowHasInterestingPrefix', () {
    test('matches prompt and choice prefixes', () {
      for (final row in ['> prompt', '} brace', '1. one', '2. two', '3. three', '◆ diamond', '❯ arrow']) {
        expect(terminalRowHasInterestingPrefix(row), isTrue, reason: row);
      }
    });

    test('does not match plain rows', () {
      for (final row in ['', 'plain output', 'x> y', '10. ten', '.1 dot', '4. four']) {
        expect(terminalRowHasInterestingPrefix(row), isFalse, reason: row);
      }
    });
  });

  group('terminalRowHasInterestingMarker', () {
    test('matches trust prompts and TUI glyphs', () {
      for (final row in [
        'Confirm folder trust',
        'Do you trust this folder?',
        'Yes, proceed',
        'No (Esc)',
        'a ◆ b',
        'a ❯ b',
        'a → b',
        '┌ top',
        '├ mid',
        '└ bottom',
        '│ side',
      ]) {
        expect(terminalRowHasInterestingMarker(row), isTrue, reason: row);
      }
    });

    test('does not match plain rows or lowercase yes', () {
      for (final row in ['', 'plain output', 'yes lowercase', 'escape only']) {
        expect(terminalRowHasInterestingMarker(row), isFalse, reason: row);
      }
    });
  });

  group('isInterestingTerminalRow', () {
    test('strips carriage returns and left whitespace before matching', () {
      expect(isInterestingTerminalRow('\r   > prompt'), isTrue);
      expect(isInterestingTerminalRow('   ❯ choice'), isTrue);
      expect(isInterestingTerminalRow('\rplain row'), isFalse);
    });

    test('combines prefix and marker rules', () {
      expect(isInterestingTerminalRow('1. first'), isTrue);
      expect(isInterestingTerminalRow('... Do you trust?'), isTrue);
      expect(isInterestingTerminalRow('boring'), isFalse);
    });
  });

  group('collectTerminalDiagnosticRows', () {
    String plain(int row) => 'row $row';

    test('includes rows around cursor and visible edges', () {
      final rows = collectTerminalDiagnosticRows(
        visibleStart: 10,
        visibleEnd: 20,
        cursorRow: 15,
        lineCount: 100,
        textAt: plain,
      );
      expect(rows, [9, 10, 11, 14, 15, 16, 19, 20, 21]);
    });

    test('clamps candidates to valid buffer range', () {
      final rows = collectTerminalDiagnosticRows(
        visibleStart: 0,
        visibleEnd: 1,
        cursorRow: 0,
        lineCount: 2,
        textAt: plain,
      );
      expect(rows, [0, 1]);
    });

    test('dumps all visible rows when any row is interesting', () {
      final rows = collectTerminalDiagnosticRows(
        visibleStart: 5,
        visibleEnd: 8,
        cursorRow: 0,
        lineCount: 20,
        textAt: (row) => row == 7 ? '> prompt' : 'row $row',
      );
      // Cursor surroundings (0,1), edge surroundings (4,9) and every
      // visible row 5..8 because row 7 looks like an interactive prompt.
      expect(rows, [0, 1, 4, 5, 6, 7, 8, 9]);
    });

    test('caps the result at 30 sorted rows', () {
      final rows = collectTerminalDiagnosticRows(
        visibleStart: 0,
        visibleEnd: 49,
        cursorRow: 25,
        lineCount: 50,
        textAt: (row) => '❯ row $row',
      );
      expect(rows.length, 30);
      expect(rows, List<int>.generate(30, (i) => i));
    });
  });

  group('sanitizeTerminalLogText', () {
    test('escapes control characters', () {
      expect(
        sanitizeTerminalLogText('a\x1bb\rc\nd'),
        r'a\x1bb\rc\nd',
      );
    });

    test('truncates text longer than 160 characters', () {
      final long = 'x' * 200;
      final result = sanitizeTerminalLogText(long);
      expect(result.length, 163);
      expect(result.endsWith('...'), isTrue);
      expect(result, '${'x' * 160}...');
    });

    test('keeps short text untouched', () {
      expect(sanitizeTerminalLogText('short'), 'short');
    });
  });

  group('debugTerminalCellChar', () {
    test('renders special codepoints', () {
      expect(debugTerminalCellChar(0), '0x0');
      expect(debugTerminalCellChar(0x20), '<sp>');
    });

    test('renders printable ASCII as-is', () {
      expect(debugTerminalCellChar(0x41), 'A');
      expect(debugTerminalCellChar(0x7E), '~');
    });

    test('renders non-printable codepoints as hex', () {
      expect(debugTerminalCellChar(0x7F), '0x7f');
      expect(debugTerminalCellChar(0xE9), '0xe9');
    });
  });

  group('dumpXtermCellDiagnostics', () {
    test('returns dash for a blank line', () {
      final line = xterm_buffer.BufferLine(10);
      expect(dumpXtermCellDiagnostics(line, maxCols: 10), '-');
    });

    test('dumps written cells with codepoint and width', () {
      final line = _lineWith('hi');
      expect(
        dumpXtermCellDiagnostics(line, maxCols: 10),
        '0:h/w1/f0/fg0/bg0 | 1:i/w1/f0/fg0/bg0',
      );
    });

    test('honors the maxCols cap', () {
      final line = _lineWith('abcdef');
      expect(
        dumpXtermCellDiagnostics(line, maxCols: 3),
        '0:a/w1/f0/fg0/bg0 | 1:b/w1/f0/fg0/bg0 | 2:c/w1/f0/fg0/bg0',
      );
    });

    test('includes zero-codepoint cells with attributes before column 6', () {
      final line = xterm_buffer.BufferLine(10);
      final style = xterm_cursor.CursorStyle()..setBold();
      line.setCell(2, 0, 1, style);
      final dump = dumpXtermCellDiagnostics(line, maxCols: 10);
      expect(dump, startsWith('2:0x0/w1/f'));
    });

    test('skips zero-codepoint plain cells at column 6 and beyond', () {
      final line = xterm_buffer.BufferLine(10);
      line.setCell(7, 0, 1, xterm_cursor.CursorStyle());
      expect(dumpXtermCellDiagnostics(line, maxCols: 10), '-');
    });

    test('caps the number of dumped cells at 40', () {
      final line = _lineWith('x' * 60);
      final dump = dumpXtermCellDiagnostics(line, maxCols: 60);
      expect(' | '.allMatches(dump).length, 39);
    });
  });
}
