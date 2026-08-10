import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_plugin.dart';

import '../../../unit/helpers/mock_board_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panelId = 'timer_ticker_panel';

  BoardPanelInstance panel({required bool isRunning}) => BoardPanelInstance(
    id: panelId,
    type: TimerPlugin.kTypeId,
    title: 'Timer',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 320),
    state: <String, dynamic>{
      'duration': 300,
      'remaining': 300,
      'isRunning': isRunning,
      'isPaused': false,
      'completed': false,
      'label': '',
      'lastTick': DateTime.now().millisecondsSinceEpoch,
    },
  );

  MockBoardCubit cubitWith(BoardPanelInstance panel) {
    final cubit = MockBoardCubit();
    when(
      () => cubit.stream,
    ).thenAnswer((_) => const Stream<BoardState>.empty());
    when(() => cubit.state).thenReturn(
      BoardState(
        boards: <BoardDocument>[
          BoardDocument(id: 'b1', name: 'Board', panels: <BoardPanelInstance>[panel]),
        ],
        activeBoardId: 'b1',
        isLoaded: true,
      ),
    );
    when(
      () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
    ).thenAnswer((_) async {});
    return cubit;
  }

  Future<void> pumpTimer(
    WidgetTester tester,
    BoardPanelInstance panel,
    MockBoardCubit cubit,
    List<Map<String, dynamic>> updates,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: BlocProvider<BoardCubit>.value(
          value: cubit,
          child: Scaffold(
            body: SizedBox(
              width: 300,
              height: 320,
              child: Builder(
                builder:
                    (ctx) => const TimerPlugin().buildContent(
                      ctx,
                      panel,
                      BoardPanelRenderContext(
                        isSelected: false,
                        onFocus: () {},
                        onDelete: () {},
                        onUpdateState: updates.add,
                        onShowEditor: () {},
                      ),
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  tearDown(() {
    TimerManager.instance.stop(panelId);
  });

  testWidgets('running timer starts a ticker that writes state updates', (
    tester,
  ) async {
    final timerPanel = panel(isRunning: true);
    final updates = <Map<String, dynamic>>[];
    final cubit = cubitWith(timerPanel);

    await pumpTimer(tester, timerPanel, cubit, updates);
    await tester.pump();

    // _startTicker registered the countdown with the manager (survives
    // widget dispose) and shows the dial.
    expect(TimerManager.instance.isRunning(panelId), isTrue);
    expect(find.text('05:00'), findsOneWidget);

    // Fire the local UI ticker once; it reports the running countdown back
    // through the render context.
    await tester.pump(const Duration(milliseconds: 1100));

    expect(updates, isNotEmpty);
    expect(updates.last['remaining'], 300);
    expect(updates.last['isRunning'], isTrue);
    expect(updates.last['completed'], isFalse);

    // Disposing the widget stops the local ticker but the manager keeps the
    // countdown alive.
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(TimerManager.instance.isRunning(panelId), isTrue);
    TimerManager.instance.stop(panelId);
  });

  testWidgets('idle timer does not register with the manager', (tester) async {
    final timerPanel = panel(isRunning: false);
    final updates = <Map<String, dynamic>>[];
    final cubit = cubitWith(timerPanel);

    await pumpTimer(tester, timerPanel, cubit, updates);
    await tester.pump();

    expect(TimerManager.instance.isRunning(panelId), isFalse);
    expect(find.text('05:00'), findsOneWidget);

    // No ticker fires: no state updates are produced over time.
    await tester.pump(const Duration(seconds: 2));
    expect(updates, isEmpty);
  });
}
