import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;

import '../board_view_test_harness.dart';
import 'board_terminal_panel_test_harness.dart';

class _RecordingMouseHandler extends TerminalMouseHandler {
  _RecordingMouseHandler(this.onWheel);

  final VoidCallback onWheel;

  @override
  String? call(TerminalMouseEvent event) {
    if (event.button == TerminalMouseButton.wheelUp ||
        event.button == TerminalMouseButton.wheelDown) {
      onWheel();
    }
    return null;
  }
}

/// Regression test against the REAL [BoardView]: scrolling the terminal's
/// scrollback with the mouse wheel must keep working after switching boards
/// and back. Reported bug: after a board switch the wheel zooms/pans the
/// board canvas but the terminal itself no longer scrolls.
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

  Future<double> terminalScrollOffset(WidgetTester tester) async {
    final terminalView = tester.widget<TerminalView>(
      find.byType(TerminalView),
    );
    final controller = terminalView.scrollController!;
    await tester.pump();
    return controller.hasClients ? controller.offset : -1;
  }

  Future<void> wheelOverTerminal(WidgetTester tester, Offset delta) async {
    final center = tester.getCenter(find.byType(TerminalView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.pump();
    await tester.sendEventToBinding(pointer.scroll(delta));
    await tester.pump();
  }

  testWidgets('terminal wheel scroll survives a board switch', (tester) async {
    final manager = BoardTerminalSessionManager.instance;
    manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));

    final panel = terminalPanel(
      sessionId: 'sess-1',
      sessionName: 'demo',
      workingDir: '/tmp/demo',
    );
    final boardA = boardTestBoard(
      id: 'board-a',
      name: 'A',
      panels: [panel],
    );
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
    var wheelEvents = 0;
    session.terminal.mouseHandler = _RecordingMouseHandler(() => wheelEvents++);

    // The session starts as a normal shell: wheel scrolls the scrollback.
    for (var i = 0; i < 40; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump();
    await tester.pump();
    final scrollbackBefore = await terminalScrollOffset(tester);
    await wheelOverTerminal(tester, const Offset(0, -120));
    expect(
      ((await terminalScrollOffset(tester)) - scrollbackBefore).abs(),
      greaterThan(20),
      reason: 'wheel must scroll the scrollback in normal mode',
    );

    // Then the user starts a TUI (claude code etc.): the app enters the
    // alternate screen buffer via the ?1049h escape sequence mid-session
    // and reports mouse wheels.
    session.terminal.write('\x1b[?1049h');
    await tester.pump();
    await tester.pump();
    wheelEvents = 0;
    await wheelOverTerminal(tester, const Offset(0, -120));
    expect(
      wheelEvents,
      greaterThan(0),
      reason:
          'wheel over a TUI terminal must deliver wheel mouse events '
          '(alt-buffer scroll)',
    );

    // Move the pointer off the panel so the hover lock exits before the
    // switch, like a real user clicking the board switcher.
    final away = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(away.hover(const Offset(20, 20)));
    await tester.pump(const Duration(milliseconds: 150));

    // Switch to board B, then back to A — mirrors the user flow.
    await cubit.setActiveBoard('board-b');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TerminalView), findsNothing);

    await cubit.setActiveBoard('board-a');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TerminalWidget), findsOneWidget);

    final wheelEventsBeforeSwitch = wheelEvents;
    await wheelOverTerminal(tester, const Offset(0, -120));
    expect(
      wheelEvents,
      greaterThan(wheelEventsBeforeSwitch),
      reason:
          'REGRESSION: wheel over a TUI terminal must still deliver wheel '
          'mouse events after switching boards — the canvas zoom must not '
          'be the only thing consuming the wheel',
    );
  });

  testWidgets('restored SGR mouse modes route wheel after remount and resize',
      (tester) async {
    final backend = FakeTerminalBackend()
      ..attachedExisting = true
      ..attachedModes = const [1049, 1002, 1006];
    TerminalBackendService.instance.debugBackendOverride = backend;
    addTearDown(() {
      TerminalBackendService.instance.debugBackendOverride = null;
    });
    addTearDown(backend.closeIfLaunched);

    final manager = BoardTerminalSessionManager.instance;
    final session = await manager.ensureSession(
      const BoardTerminalConfig(
        sessionId: 'sess-sgr',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      ),
    );
    expect(session.terminal.isUsingAltBuffer, isTrue);

    final panel = terminalPanel(
      sessionId: 'sess-sgr',
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

    int wheelReports() => backend.writes
        .where(
          (data) => data.contains('\x1b[<64;') || data.contains('\x1b[<65;'),
        )
        .length;

    setBoardViewSurface(tester);
    await pumpBoardView(tester, cubit);
    await tester.pump(const Duration(milliseconds: 500));
    await wheelOverTerminal(tester, const Offset(0, -120));
    expect(
      wheelReports(),
      greaterThan(0),
      reason: '1049+1002+1006 must produce SGR wheel reports on mount',
    );

    await cubit.setActiveBoard('board-b');
    await tester.pump(const Duration(milliseconds: 500));
    await cubit.setActiveBoard('board-a');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(TerminalWidget), findsOneWidget);

    // Exercise a real emulator resize as well as the remount: neither may
    // clear the restored alt-buffer/mouse-reporting state used by the
    // pointer-signal resolver.
    session.terminal.resize(
      session.terminal.viewWidth + 1,
      session.terminal.viewHeight,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final beforeWheel = wheelReports();
    await wheelOverTerminal(tester, const Offset(0, 120));
    expect(wheelReports(), greaterThan(beforeWheel));
  });
}
