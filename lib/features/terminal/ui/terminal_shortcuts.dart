import 'package:flutter/services.dart';

/// Result of mapping a keyboard shortcut to a terminal action.
///
/// Either a PTY escape sequence to write ([TerminalPtyShortcut]) or a local
/// UI action to execute ([TerminalActionShortcut]).
sealed class TerminalShortcut {
  const TerminalShortcut();
}

/// Sends [sequence] to the PTY.
final class TerminalPtyShortcut extends TerminalShortcut {
  const TerminalPtyShortcut(this.sequence);

  final String sequence;
}

/// Non-sequence shortcut actions executed by the caller.
enum TerminalShortcutAction {
  /// Cmd+V — smart paste (safe short text inline, otherwise file ref).
  paste,

  /// Cmd+F — open the in-terminal search overlay.
  openSearch,

  /// Cmd+O — global quick file search.
  openFileSearch,

  /// Cmd+= — increase terminal font size.
  increaseFontSize,

  /// Cmd+- — decrease terminal font size.
  decreaseFontSize,

  /// Cmd+A — select all terminal buffer content.
  selectAll,

  /// Cmd+C — copy the current selection.
  copySelection,

  /// Cmd+V seen by xterm's onKeyEvent — block xterm's native paste so text
  /// isn't inserted twice (the paste itself is handled by the hardware-key
  /// shortcut via [TerminalShortcutAction.paste]).
  blockNativePaste,

  /// Plain Enter while awaiting approval — signal ThinkingPhase immediately.
  notifyEnterPressed,
}

/// Executes a local UI [action] instead of writing to the PTY.
final class TerminalActionShortcut extends TerminalShortcut {
  const TerminalActionShortcut(this.action);

  final TerminalShortcutAction action;
}

/// Maps macOS hardware-keyboard shortcuts to PTY control sequences or local
/// actions. Pure translation — the caller executes the returned result.
///
/// Mapping (readline / bash compatible):
///   Ctrl+C             → SIGINT   (\x03)
///   Cmd+V              → smart paste: safe short text inline, otherwise file ref
///   Cmd+Backspace      → Ctrl+U  (\x15) — erase to start of line
///   Opt+Backspace      → Ctrl+W  (\x17) — erase word backward
///   Ctrl+Backspace     → Ctrl+W  (\x17) — erase word backward (PC style)
///   Cmd+←             → Ctrl+A  (\x01) — beginning of line
///   Cmd+→             → Ctrl+E  (\x05) — end of line
///   Opt+←             → ESC+b   (\x1bb) — word backward
///   Opt+→             → ESC+f   (\x1bf) — word forward
///   Cmd+K             → Ctrl+L  (\x0c) — clear screen
TerminalShortcut? terminalShortcutSequence(
  LogicalKeyboardKey key, {
  required bool isCmd,
  required bool isCtrl,
  required bool isAlt,
  required bool hasSelection,
}) {
  // Ctrl+C → SIGINT. Handle explicitly so Flutter focus/copy shortcuts cannot
  // swallow it before the terminal backend sees ETX.
  if (isCtrl && !isCmd && !isAlt && key == LogicalKeyboardKey.keyC) {
    return const TerminalPtyShortcut('\x03');
  }

  // Cmd+V → smart paste (safe short text inline, otherwise file ref).
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyV) {
    return const TerminalActionShortcut(TerminalShortcutAction.paste);
  }

  // Cmd+Backspace → erase to start of line (Ctrl+U)
  if (isCmd && key == LogicalKeyboardKey.backspace) {
    return const TerminalPtyShortcut('\x15');
  }

  // Option+Backspace or Ctrl+Backspace → erase word backward (Ctrl+W)
  if ((isAlt || isCtrl) && key == LogicalKeyboardKey.backspace) {
    return const TerminalPtyShortcut('\x17');
  }

  // Cmd+Left → beginning of line (Ctrl+A)
  if (isCmd && key == LogicalKeyboardKey.arrowLeft) {
    return const TerminalPtyShortcut('\x01');
  }

  // Cmd+Right → end of line (Ctrl+E)
  if (isCmd && key == LogicalKeyboardKey.arrowRight) {
    return const TerminalPtyShortcut('\x05');
  }

  // Option+Left → word backward (ESC b)
  if (isAlt && key == LogicalKeyboardKey.arrowLeft) {
    return const TerminalPtyShortcut('\x1bb');
  }

  // Option+Right → word forward (ESC f)
  if (isAlt && key == LogicalKeyboardKey.arrowRight) {
    return const TerminalPtyShortcut('\x1bf');
  }

  // Cmd+K → clear screen (Ctrl+L)
  if (isCmd && key == LogicalKeyboardKey.keyK) {
    return const TerminalPtyShortcut('\x0c');
  }

  // Cmd+F → open search
  if (isCmd && key == LogicalKeyboardKey.keyF) {
    return const TerminalActionShortcut(TerminalShortcutAction.openSearch);
  }

  // Cmd+O → global quick file search (prevent terminal from swallowing it)
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyO) {
    return const TerminalActionShortcut(TerminalShortcutAction.openFileSearch);
  }

  // Cmd+= → increase font size
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.equal) {
    return const TerminalActionShortcut(
      TerminalShortcutAction.increaseFontSize,
    );
  }

  // Cmd+- → decrease font size
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.minus) {
    return const TerminalActionShortcut(
      TerminalShortcutAction.decreaseFontSize,
    );
  }

  // Cmd+A → select all terminal buffer content
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyA) {
    return const TerminalActionShortcut(TerminalShortcutAction.selectAll);
  }

  // Cmd+C → copy selection if one exists; otherwise let xterm send ^C
  if (isCmd && !isCtrl && !isAlt && key == LogicalKeyboardKey.keyC) {
    if (hasSelection) {
      return const TerminalActionShortcut(TerminalShortcutAction.copySelection);
    }
    // No selection — fall through so xterm sends ^C (SIGINT)
  }

  return null;
}

/// Maps key events seen by xterm's `onKeyEvent` (before [TerminalView]
/// processes the raw key event) to PTY control sequences or local actions.
///
/// xterm onKeyEvent — intercepts Shift+Enter to send the Kitty keyboard
/// protocol escape sequence (\x1b[13;2u) so modern CLIs (Copilot, Claude
/// Code) treat it as a newline in the input buffer instead of submitting.
TerminalShortcut? terminalKeyEventShortcut(
  LogicalKeyboardKey key, {
  required bool isShift,
  required bool isCmd,
  required bool isCtrl,
  required bool isAlt,
  required bool awaitingApproval,
}) {
  if (key == LogicalKeyboardKey.keyC && isCtrl && !isCmd && !isAlt) {
    return const TerminalPtyShortcut('\x03');
  }
  // Shift+Enter → ESC+CR (newline-in-input for Copilot/Claude Code)
  if (key == LogicalKeyboardKey.enter &&
      isShift &&
      !isCmd &&
      !isCtrl &&
      !isAlt) {
    return const TerminalPtyShortcut('\x1b\r');
  }
  // Plain Enter while awaiting approval → immediately signal ThinkingPhase.
  if (key == LogicalKeyboardKey.enter &&
      !isShift &&
      !isCmd &&
      !isCtrl &&
      !isAlt &&
      awaitingApproval) {
    return const TerminalActionShortcut(
      TerminalShortcutAction.notifyEnterPressed,
    );
  }
  // Cmd+V — already handled by terminalShortcutSequence; block xterm's native
  // paste so text isn't inserted twice.
  if (key == LogicalKeyboardKey.keyV && isCmd && !isCtrl && !isAlt) {
    return const TerminalActionShortcut(
      TerminalShortcutAction.blockNativePaste,
    );
  }
  return null;
}
