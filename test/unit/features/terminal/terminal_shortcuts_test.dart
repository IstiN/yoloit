import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/ui/terminal_shortcuts.dart';

TerminalShortcut? _hw(
  LogicalKeyboardKey key, {
  bool cmd = false,
  bool ctrl = false,
  bool alt = false,
  bool selection = false,
}) {
  return terminalShortcutSequence(
    key,
    isCmd: cmd,
    isCtrl: ctrl,
    isAlt: alt,
    hasSelection: selection,
  );
}

TerminalShortcut? _ke(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool cmd = false,
  bool ctrl = false,
  bool alt = false,
  bool approval = false,
}) {
  return terminalKeyEventShortcut(
    key,
    isShift: shift,
    isCmd: cmd,
    isCtrl: ctrl,
    isAlt: alt,
    awaitingApproval: approval,
  );
}

void main() {
  group('terminalShortcutSequence', () {
    test('Ctrl+C → SIGINT', () {
      final result = _hw(LogicalKeyboardKey.keyC, ctrl: true);
      expect(result, isA<TerminalPtyShortcut>());
      expect((result! as TerminalPtyShortcut).sequence, '\x03');
    });

    test('Ctrl+Cmd+C → unhandled (Ctrl+C rule forbids Cmd)', () {
      expect(_hw(LogicalKeyboardKey.keyC, ctrl: true, cmd: true), isNull);
    });

    test('Ctrl+Alt+C → unhandled (Ctrl+C rule forbids Alt)', () {
      expect(_hw(LogicalKeyboardKey.keyC, ctrl: true, alt: true), isNull);
    });

    test('plain C → unhandled', () {
      expect(_hw(LogicalKeyboardKey.keyC), isNull);
    });

    test('Cmd+V → smart paste', () {
      final result = _hw(LogicalKeyboardKey.keyV, cmd: true);
      expect(result, isA<TerminalActionShortcut>());
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.paste,
      );
    });

    test('Cmd+Ctrl+V → unhandled', () {
      expect(_hw(LogicalKeyboardKey.keyV, cmd: true, ctrl: true), isNull);
    });

    test('Cmd+Alt+V → unhandled', () {
      expect(_hw(LogicalKeyboardKey.keyV, cmd: true, alt: true), isNull);
    });

    test('Cmd+Backspace → Ctrl+U (erase to start of line)', () {
      final result = _hw(LogicalKeyboardKey.backspace, cmd: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x15');
    });

    test('Cmd+Alt+Backspace → Ctrl+U (Cmd rule wins by fallthrough order)', () {
      final result = _hw(LogicalKeyboardKey.backspace, cmd: true, alt: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x15');
    });

    test('Cmd+Ctrl+Backspace → Ctrl+U (Cmd rule wins by fallthrough order)', () {
      final result = _hw(LogicalKeyboardKey.backspace, cmd: true, ctrl: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x15');
    });

    test('Alt+Backspace → Ctrl+W (erase word backward)', () {
      final result = _hw(LogicalKeyboardKey.backspace, alt: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x17');
    });

    test('Ctrl+Backspace → Ctrl+W (PC style)', () {
      final result = _hw(LogicalKeyboardKey.backspace, ctrl: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x17');
    });

    test('plain Backspace → unhandled', () {
      expect(_hw(LogicalKeyboardKey.backspace), isNull);
    });

    test('Cmd+Left → Ctrl+A (beginning of line)', () {
      final result = _hw(LogicalKeyboardKey.arrowLeft, cmd: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x01');
    });

    test('Cmd+Alt+Left → Ctrl+A (Cmd rule precedes Alt rule)', () {
      final result = _hw(LogicalKeyboardKey.arrowLeft, cmd: true, alt: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x01');
    });

    test('Cmd+Right → Ctrl+E (end of line)', () {
      final result = _hw(LogicalKeyboardKey.arrowRight, cmd: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x05');
    });

    test('Alt+Left → ESC+b (word backward)', () {
      final result = _hw(LogicalKeyboardKey.arrowLeft, alt: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x1bb');
    });

    test('Alt+Right → ESC+f (word forward)', () {
      final result = _hw(LogicalKeyboardKey.arrowRight, alt: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x1bf');
    });

    test('plain Left → unhandled', () {
      expect(_hw(LogicalKeyboardKey.arrowLeft), isNull);
    });

    test('Cmd+K → Ctrl+L (clear screen)', () {
      final result = _hw(LogicalKeyboardKey.keyK, cmd: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x0c');
    });

    test('Cmd+Ctrl+K → Ctrl+L (Cmd+K rule has no Ctrl/Alt guard)', () {
      final result = _hw(LogicalKeyboardKey.keyK, cmd: true, ctrl: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x0c');
    });

    test('Cmd+F → open search', () {
      final result = _hw(LogicalKeyboardKey.keyF, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.openSearch,
      );
    });

    test('Cmd+O → open file search', () {
      final result = _hw(LogicalKeyboardKey.keyO, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.openFileSearch,
      );
    });

    test('Cmd+Ctrl+O → unhandled', () {
      expect(_hw(LogicalKeyboardKey.keyO, cmd: true, ctrl: true), isNull);
    });

    test('Cmd+= → increase font size', () {
      final result = _hw(LogicalKeyboardKey.equal, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.increaseFontSize,
      );
    });

    test('Cmd+Ctrl+= → unhandled', () {
      expect(_hw(LogicalKeyboardKey.equal, cmd: true, ctrl: true), isNull);
    });

    test('Cmd+- → decrease font size', () {
      final result = _hw(LogicalKeyboardKey.minus, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.decreaseFontSize,
      );
    });

    test('Cmd+A → select all', () {
      final result = _hw(LogicalKeyboardKey.keyA, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.selectAll,
      );
    });

    test('Cmd+Ctrl+A → unhandled', () {
      expect(_hw(LogicalKeyboardKey.keyA, cmd: true, ctrl: true), isNull);
    });

    test('Cmd+C with selection → copy selection', () {
      final result = _hw(LogicalKeyboardKey.keyC, cmd: true, selection: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.copySelection,
      );
    });

    test('Cmd+C without selection → unhandled (xterm sends ^C)', () {
      expect(_hw(LogicalKeyboardKey.keyC, cmd: true), isNull);
    });
  });

  group('terminalKeyEventShortcut', () {
    test('Ctrl+C → SIGINT', () {
      final result = _ke(LogicalKeyboardKey.keyC, ctrl: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x03');
    });

    test('Ctrl+Cmd+C → unhandled', () {
      expect(_ke(LogicalKeyboardKey.keyC, ctrl: true, cmd: true), isNull);
    });

    test('Shift+Enter → ESC+CR (Kitty-style newline-in-input)', () {
      final result = _ke(LogicalKeyboardKey.enter, shift: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x1b\r');
    });

    test('Shift+Enter while awaiting approval → ESC+CR (Shift rule first)', () {
      final result = _ke(LogicalKeyboardKey.enter, shift: true, approval: true);
      expect((result! as TerminalPtyShortcut).sequence, '\x1b\r');
    });

    test('plain Enter while awaiting approval → notify enter pressed', () {
      final result = _ke(LogicalKeyboardKey.enter, approval: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.notifyEnterPressed,
      );
    });

    test('plain Enter without approval → unhandled', () {
      expect(_ke(LogicalKeyboardKey.enter), isNull);
    });

    test('Shift+Ctrl+Enter → unhandled', () {
      expect(_ke(LogicalKeyboardKey.enter, shift: true, ctrl: true), isNull);
    });

    test('Cmd+V → block native paste', () {
      final result = _ke(LogicalKeyboardKey.keyV, cmd: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.blockNativePaste,
      );
    });

    test('Shift+Cmd+V → block native paste (Shift not guarded)', () {
      final result = _ke(LogicalKeyboardKey.keyV, cmd: true, shift: true);
      expect(
        (result! as TerminalActionShortcut).action,
        TerminalShortcutAction.blockNativePaste,
      );
    });

    test('Cmd+Ctrl+V → unhandled', () {
      expect(_ke(LogicalKeyboardKey.keyV, cmd: true, ctrl: true), isNull);
    });

    test('plain V → unhandled', () {
      expect(_ke(LogicalKeyboardKey.keyV), isNull);
    });

    test('unrelated key → unhandled', () {
      expect(_ke(LogicalKeyboardKey.keyQ), isNull);
    });
  });
}
