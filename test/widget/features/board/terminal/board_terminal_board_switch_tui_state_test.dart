import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;

import 'board_terminal_panel_test_harness.dart';
import '../board_view_test_harness.dart';

/// Regression tests for the mixed-frame TUI artifact after a board switch.
///
/// Symptom: switching boards and back left an alt-buffer TUI (Fa, differential
/// rendering) with old and new frames interleaved — the previous prompt line
/// and the current one visible at once, status text overwritten mid-line —
/// persisting until a manual resize forced a full redraw via SIGWINCH.
///
/// Root cause: remounting the terminal view re-runs
/// [RenderTerminal._resizeTerminalIfNeeded] with UNCHANGED cell dimensions.
/// [Terminal.resize] nevertheless mutated emulator state: it reset the
/// DECSTBM vertical scroll margins on both buffers (and cleared alt
/// scrollback). The PTY never saw a size change, so the TUI got no SIGWINCH
/// and kept writing differential updates assuming its scroll region was
/// intact — old and new content interleaved indefinitely.
///
/// Second vector: with a custom terminal font size, the first remount frame
/// used the default 13pt metrics until the async prefs load landed, causing
/// REAL transient resizes (custom -> default -> custom) whose net PTY size
/// change is zero — again no SIGWINCH, but the grid's scroll region was
/// reset. TerminalWidget now seeds the font size from the prefs cache
/// synchronously, so a remount never changes cell metrics.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  setUp(() {
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
    CanvasInteractionLock.instance.resetForTesting();
  });

  Future<void> runScenario(WidgetTester tester) async {
    final manager = BoardTerminalSessionManager.instance;
    manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));

    final panel = terminalPanel(
      sessionId: 'sess-1',
      sessionName: 'demo',
      workingDir: '/tmp/demo',
    );
    final boardA = boardTestBoard(id: 'board-a', name: 'A', panels: [panel]);
    final boardB = boardTestBoard(id: 'board-b', name: 'B');
    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardA, boardB],
        activeBoardId: 'board-a',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);

    setBoardViewSurface(tester);
    await pumpBoardView(tester, cubit);
    expect(find.byType(TerminalWidget), findsOneWidget);

    final session = manager.sessionFor('sess-1')!;
    final terminal = session.terminal;

    // A fullscreen TUI starts: alternate buffer, differential frames.
    terminal.write('\x1b[?1049h');
    await tester.pump();
    // Let the initial view-driven resizes settle (200ms alt debounce +
    // 150ms backend debounce) BEFORE the TUI configures its layout, as
    // happens in a real session after SIGWINCH.
    await tester.pump(const Duration(milliseconds: 500));

    final rows = terminal.viewHeight;
    final cols = terminal.viewWidth;
    expect(rows, greaterThan(6));

    // TUI layout: a scroll region covering all but the last two rows and
    // a fixed status/prompt block at the bottom.
    terminal.write('\x1b[1;${rows - 2}r');
    terminal.write('\x1b[${rows - 1};1HSTATUS-OLD');
    terminal.write('\x1b[$rows;1HPROMPT-55%');
    await tester.pump();

    expect(terminal.buffer.marginBottom, rows - 3);

    String statusLine() =>
        terminal.buffer.lines[terminal.viewHeight - 2].getText().trim();
    String promptLine() =>
        terminal.buffer.lines[terminal.viewHeight - 1].getText().trim();
    expect(statusLine(), 'STATUS-OLD');
    expect(promptLine(), 'PROMPT-55%');

    // Switch to board B and back to A — mirrors the user flow.
    await cubit.setActiveBoard('board-b');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TerminalWidget), findsNothing);

    await cubit.setActiveBoard('board-a');
    await tester.pump();
    // Fire the remount resize debounce (alt buffer: 200ms) and the
    // backend resize debounce (150ms) if any.
    await tester.pump(const Duration(milliseconds: 500));

    expect(
      terminal.isUsingAltBuffer,
      isTrue,
      reason: 'the TUI is still running in the alternate buffer',
    );
    expect(
      terminal.viewWidth,
      cols,
      reason: 'panel size did not change across the board switch',
    );
    expect(terminal.viewHeight, rows);
    expect(
      terminal.buffer.marginTop,
      0,
      reason:
          'REGRESSION: a same-size remount resize must not reset the '
          'TUI scroll region',
    );
    expect(
      terminal.buffer.marginBottom,
      rows - 3,
      reason:
          'REGRESSION: DECSTBM margins were reset by a spurious resize on '
          'remount; the TUI receives no SIGWINCH for it, so its '
          'differential frames interleave with stale content forever',
    );
    expect(statusLine(), 'STATUS-OLD');
    expect(promptLine(), 'PROMPT-55%');

    // The TUI keeps producing differential frames after the switch: the
    // fixed bottom block must stay exactly where the TUI put it.
    terminal.write('\x1b[${rows - 1};1HSTATUS-NEW');
    terminal.write('\x1b[$rows;1HPROMPT-65%');
    await tester.pump();
    expect(statusLine(), 'STATUS-NEW');
    expect(promptLine(), 'PROMPT-65%');
  }

  testWidgets(
    'alt-buffer TUI scroll region and content survive a board switch',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      await runScenario(tester);
    },
  );

  testWidgets(
    'alt-buffer TUI survives a board switch with a custom terminal font',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'session.terminalFontSize': 18.0,
      });
      await runScenario(tester);
    },
  );
}
