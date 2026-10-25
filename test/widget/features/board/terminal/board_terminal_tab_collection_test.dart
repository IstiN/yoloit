import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_full_view.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

import 'board_terminal_panel_test_harness.dart';

BoardPanelInstance _terminal(
  String id, {
  required String title,
  required String sessionId,
  String sessionName = '',
  bool hidden = false,
}) {
  return BoardPanelInstance(
    id: id,
    type: 'board.terminal',
    title: title,
    hidden: hidden,
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 520, height: 400),
    state: <String, dynamic>{
      'config': <String, dynamic>{
        'sessionId': sessionId,
        'sessionName': sessionName,
        'workingDir': '/tmp/$id',
        'envGroupIds': <String>[],
      },
    },
  );
}

Finder _tabTooltip(String title) {
  return find.byWidgetPredicate(
    (widget) => widget is Tooltip && widget.message == title,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
    CanvasInteractionLock.instance.resetForTesting();
  });

  testWidgets('full view collects only visible terminals with live sessions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final manager = BoardTerminalSessionManager.instance;
    for (final id in <String>[
      'session-current',
      'session-custom',
      'session-named',
      'session-default',
      'session-hidden',
    ]) {
      manager.setSessionForTesting(id, liveTerminalSession(id));
    }

    final current = _terminal(
      'term-current',
      title: 'Current terminal',
      sessionId: 'session-current',
    );
    final board = BoardDocument(
      id: 'board-tabs',
      name: 'Terminal tabs',
      panels: <BoardPanelInstance>[
        current,
        _terminal(
          'term-custom',
          title: 'Custom title',
          sessionId: 'session-custom',
          sessionName: 'Unused session name',
        ),
        _terminal(
          'term-named',
          title: '   ',
          sessionId: 'session-named',
          sessionName: 'Session fallback',
        ),
        _terminal(
          'term-default',
          title: '',
          sessionId: 'session-default',
          sessionName: '  ',
        ),
        _terminal(
          'term-hidden',
          title: 'Hidden terminal',
          sessionId: 'session-hidden',
          hidden: true,
        ),
        _terminal(
          'term-missing',
          title: 'Missing session',
          sessionId: 'session-missing',
        ),
        _terminal('term-empty', title: 'Empty session', sessionId: ''),
        const BoardPanelInstance(
          id: 'note-panel',
          type: 'board.note.markdown',
          title: 'Not a terminal',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        ),
        const BoardPanelInstance(
          id: 'invalid-config',
          type: 'board.terminal',
          title: 'Invalid config',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: <String, dynamic>{'config': 'invalid'},
        ),
      ],
    );
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(
        boards: <BoardDocument>[board],
        activeBoardId: board.id,
        isLoaded: true,
      ),
    );

    await pumpTerminalPanel(tester, panel: current, cubit: cubit);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.byType(BoardTerminalFullView), findsOneWidget);
    expect(_tabTooltip('Current terminal'), findsOneWidget);
    expect(_tabTooltip('Custom title'), findsOneWidget);
    expect(_tabTooltip('Session fallback'), findsOneWidget);
    expect(_tabTooltip('Terminal'), findsOneWidget);
    expect(_tabTooltip('Hidden terminal'), findsNothing);
    expect(_tabTooltip('Missing session'), findsNothing);
    expect(_tabTooltip('Empty session'), findsNothing);
    expect(_tabTooltip('Invalid config'), findsNothing);

    await tester.tap(find.byTooltip('Close full view'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('full view uses the opening session when no board is available', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final manager = BoardTerminalSessionManager.instance;
    manager.setSessionForTesting(
      'session-current',
      liveTerminalSession('session-current'),
    );
    final current = _terminal(
      'term-current',
      title: 'Standalone terminal',
      sessionId: 'session-current',
    );
    final cubit = BoardCubit();
    addTearDown(cubit.close);

    await pumpTerminalPanel(tester, panel: current, cubit: cubit);
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await tester.pump();
    await tester.pump();

    expect(find.byType(BoardTerminalFullView), findsOneWidget);
    expect(_tabTooltip('Standalone terminal'), findsOneWidget);

    await tester.tap(find.byTooltip('Close full view'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  });
}
