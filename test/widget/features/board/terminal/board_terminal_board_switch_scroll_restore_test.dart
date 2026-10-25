import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;

import 'board_terminal_panel_test_harness.dart';
import '../board_view_test_harness.dart';

/// Regression tests for the terminal viewport after a board switch.
///
/// Reported glitch: switching boards and back made the terminal jump to the
/// bottom of the scrollback even when the user had scrolled up (worst case:
/// reading the very top of the scrollback, which is indistinguishable from a
/// fresh session by offset alone), flashing the wrong content for a frame.
///
/// Fix: AgentSession tracks hasUserScrolled explicitly and TerminalView gets
/// snapToBottomOnAttach=false in that case, so the persisted scroll offset
/// is honored on the very first layout of the remounted view.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
    CanvasInteractionLock.instance.resetForTesting();
  });

  double terminalScrollOffset(WidgetTester tester) {
    final view = tester.widget<TerminalView>(find.byType(TerminalView));
    final controller = view.scrollController!;
    return controller.hasClients ? controller.offset : -1;
  }

  Future<TestBoardViewCubit> mountTwoBoards(
    WidgetTester tester, {
    required BoardTerminalSessionManager manager,
  }) async {
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
    return cubit;
  }

  Future<void> switchAwayAndBack(
    WidgetTester tester,
    TestBoardViewCubit cubit,
  ) async {
    await cubit.setActiveBoard('board-b');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TerminalView), findsNothing);
    await cubit.setActiveBoard('board-a');
    await tester.pump();
  }

  testWidgets(
    'top-of-scrollback position survives a board switch without flashing '
    'the bottom',
    (tester) async {
      final manager = BoardTerminalSessionManager.instance;
      final cubit = await mountTwoBoards(tester, manager: manager);
      final session = manager.sessionFor('sess-1')!;
      for (var i = 0; i < 120; i++) {
        session.terminal.write('line $i\r\n');
      }
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // User scrolls to the very top of the scrollback.
      tester
          .widget<TerminalView>(find.byType(TerminalView))
          .scrollController!
          .jumpTo(0);
      await tester.pump();
      expect(terminalScrollOffset(tester), 0);
      expect(session.hasUserScrolled, isTrue);

      await switchAwayAndBack(tester, cubit);

      // Correct after the very first pump: no intermediate frame at the
      // bottom that a post-frame restore would produce.
      expect(
        terminalScrollOffset(tester),
        moreOrLessEquals(0, epsilon: 1.0),
        reason:
            'REGRESSION: a terminal scrolled to the top of the scrollback '
            'must come back at the top after a board switch, not snap to '
            'the bottom',
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(terminalScrollOffset(tester), moreOrLessEquals(0, epsilon: 1.0));
    },
  );

  testWidgets('mid-scrollback position survives a board switch',
      (tester) async {
    final manager = BoardTerminalSessionManager.instance;
    final cubit = await mountTwoBoards(tester, manager: manager);
    final session = manager.sessionFor('sess-1')!;
    for (var i = 0; i < 120; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final maxExtent = terminalScrollOffset(tester);
    expect(maxExtent, greaterThan(100));
    final target = maxExtent / 2;
    tester
        .widget<TerminalView>(find.byType(TerminalView))
        .scrollController!
        .jumpTo(target);
    await tester.pump();

    await switchAwayAndBack(tester, cubit);

    expect(
      terminalScrollOffset(tester),
      moreOrLessEquals(target, epsilon: 2.0),
      reason:
          'REGRESSION: the scroll position must be restored after a board '
          'switch',
    );
  });

  testWidgets('bottom-follow survives a board switch', (tester) async {
    final manager = BoardTerminalSessionManager.instance;
    final cubit = await mountTwoBoards(tester, manager: manager);
    final session = manager.sessionFor('sess-1')!;
    for (var i = 0; i < 120; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final maxBefore = terminalScrollOffset(tester);

    await switchAwayAndBack(tester, cubit);

    expect(
      terminalScrollOffset(tester),
      moreOrLessEquals(maxBefore, epsilon: 2.0),
      reason: 'a terminal parked at the bottom must come back at the bottom',
    );

    // New output keeps following the viewport.
    for (var i = 0; i < 10; i++) {
      session.terminal.write('tail $i\r\n');
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(
      terminalScrollOffset(tester),
      greaterThan(maxBefore + 10),
      reason: 'follow mode must keep working after a board switch',
    );
  });

  testWidgets('fresh unscrolled session still snaps to the bottom',
      (tester) async {
    final manager = BoardTerminalSessionManager.instance;
    final cubit = await mountTwoBoards(tester, manager: manager);
    final session = manager.sessionFor('sess-1')!;
    expect(session.hasUserScrolled, isFalse);

    // The session accumulates output BEFORE the user ever scrolls — a
    // remount must land at the bottom, not at offset 0 of the scrollback.
    for (var i = 0; i < 120; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final maxBefore = terminalScrollOffset(tester);
    expect(maxBefore, greaterThan(100));

    await switchAwayAndBack(tester, cubit);

    expect(
      terminalScrollOffset(tester),
      moreOrLessEquals(maxBefore, epsilon: 2.0),
      reason:
          'a session the user never scrolled must snap to the bottom and '
          'follow output after a board switch',
    );
  });
}
