import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';

import '../../helpers/mock_board_cubit.dart';

void main() {
  late TimerManager manager;

  setUp(() {
    manager = TimerManager.testInstance();
  });

  tearDown(() {
    manager.disposeAll();
  });

  group('TimerManager', () {

    test('starts and tracks timer', () {
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);
      expect(manager.isRunning('p1'), isTrue);
      expect(manager.remaining('p1'), 300);
      expect(manager.activeTimerIds, contains('p1'));
    });

    test('stop removes timer', () {
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);
      manager.stop('p1');
      expect(manager.isRunning('p1'), isFalse);
      expect(manager.remaining('p1'), isNull);
    });

    test('start replaces existing timer', () {
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 60);
      expect(manager.remaining('p1'), 60);
    });

    test('isRunning returns false for unknown panel', () {
      expect(manager.isRunning('unknown'), isFalse);
    });

    test('disposeAll clears all timers', () {
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);
      manager.start(panelId: 'p2', boardId: 'b1', remaining: 60);
      manager.disposeAll();
      expect(manager.activeTimerIds, isEmpty);
    });

    test('multiple timers run independently', () {
      manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);
      manager.start(panelId: 'p2', boardId: 'b1', remaining: 60);
      expect(manager.activeTimerIds.length, 2);
      manager.stop('p1');
      expect(manager.isRunning('p1'), isFalse);
      expect(manager.isRunning('p2'), isTrue);
    });
  });

  group('TimerManager ticking', () {
    late MockBoardCubit cubit;

    setUp(() {
      cubit = MockBoardCubit();
      when(
        () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
      ).thenAnswer((_) async {});
      when(() => cubit.state).thenAnswer(
        (_) => const BoardState(
          boards: [],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );
    });

    BoardPanelInstance Function(BoardPanelInstance) capturedUpdater(
      String panelId,
    ) {
      final captured =
          verify(
            () => cubit.updatePanel(panelId, captureAny(), boardId: 'b1'),
          ).captured;
      return captured.last as BoardPanelInstance Function(BoardPanelInstance);
    }

    const sourcePanel = BoardPanelInstance(
      id: 'p1',
      type: 'board.timer',
      title: 'Timer',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 320),
      state: {'remaining': 300, 'isRunning': true},
    );

    test('tick keeps running state when less than a second elapsed', () {
      fakeAsync((async) {
        manager.setCubit(cubit);
        manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);

        async.elapse(const Duration(seconds: 1));

        final updated = capturedUpdater('p1')(sourcePanel);
        expect(updated.state['remaining'], 300);
        expect(updated.state['isRunning'], isTrue);
        expect(updated.state['isPaused'], isFalse);
        expect(updated.state['completed'], isFalse);
        expect(updated.state['lastTick'], isA<int>());
        expect(manager.isRunning('p1'), isTrue);

        manager.stop('p1');
      });
    });

    test('tick without a cubit only advances internal bookkeeping', () {
      fakeAsync((async) {
        manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);

        async.elapse(const Duration(seconds: 1));

        verifyNever(
          () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
        );
        expect(manager.isRunning('p1'), isTrue);

        manager.stop('p1');
      });
    });

    test('tick completes an exhausted timer and stops it', () {
      // The completion path plays an alarm through `afplay`; only macOS
      // guarantees the binary exists, elsewhere the spawned process would
      // surface an unhandled async error.
      if (!Platform.isMacOS) return;
      fakeAsync((async) {
        manager.setCubit(cubit);
        manager.start(panelId: 'p1', boardId: 'b1', remaining: 0);

        async.elapse(const Duration(seconds: 1));

        final updated = capturedUpdater('p1')(sourcePanel);
        expect(updated.state['remaining'], 0);
        expect(updated.state['isRunning'], isFalse);
        expect(updated.state['completed'], isTrue);
        expect(manager.isRunning('p1'), isFalse);
      });
    });

    void stubActiveBoard(String? activeBoardId) {
      when(() => cubit.state).thenAnswer(
        (_) => BoardState(
          boards: const [],
          activeBoardId: activeBoardId,
          isLoaded: true,
        ),
      );
    }

    test('no panel writes while the board is hidden; one on becoming visible',
        () {
      fakeAsync((async) {
        // fakeAsync fakes timers, not the wall clock — drive the manager's
        // clock from the fake zone.
        final clock = async.getClock(DateTime(2024));
        manager = TimerManager.testInstance(now: clock.now);

        // p1 lives on b1, but b2 is the active visible board.
        stubActiveBoard('b2');
        manager.setCubit(cubit);
        manager.start(panelId: 'p1', boardId: 'b1', remaining: 300);

        // 3 hidden seconds: ~3 ticks, none of which may touch the panel.
        async.elapse(const Duration(seconds: 3));
        verifyNever(
          () => cubit.updatePanel(any(), any(), boardId: any(named: 'boardId')),
        );

        // The countdown itself kept accumulating while hidden.
        expect(manager.remaining('p1'), 297);

        // Board becomes visible: the next tick writes exactly once and the
        // remaining time has self-corrected to the accumulated elapsed time.
        stubActiveBoard('b1');
        async.elapse(const Duration(seconds: 1));

        final captured =
            verify(
              () => cubit.updatePanel('p1', captureAny(), boardId: 'b1'),
            ).captured;
        expect(captured, hasLength(1));
        final updated = (captured.single
            as BoardPanelInstance Function(BoardPanelInstance))(sourcePanel);
        expect(updated.state['remaining'], 296);
        expect(updated.state['isRunning'], isTrue);
        expect(updated.state['completed'], isFalse);

        // And it keeps ticking normally afterwards (2 more writes, one per
        // second).
        async.elapse(const Duration(seconds: 2));
        final captured2 =
            verify(
              () => cubit.updatePanel('p1', captureAny(), boardId: 'b1'),
            ).captured;
        expect(captured2, hasLength(2));
        expect(manager.remaining('p1'), 294);

        manager.stop('p1');
      });
    });

    test('timer completes correctly while the board is hidden', () {
      // The completion path plays an alarm through `afplay`; only macOS
      // guarantees the binary exists, elsewhere the spawned process would
      // surface an unhandled async error.
      if (!Platform.isMacOS) return;
      fakeAsync((async) {
        final clock = async.getClock(DateTime(2024));
        manager = TimerManager.testInstance(now: clock.now);

        stubActiveBoard('b2');
        manager.setCubit(cubit);
        manager.start(panelId: 'p1', boardId: 'b1', remaining: 2);

        async.elapse(const Duration(seconds: 3));

        // Hidden ticks were skipped, but the completion write always lands
        // so the UI sees the finished state once the board returns.
        final captured =
            verify(
              () => cubit.updatePanel('p1', captureAny(), boardId: 'b1'),
            ).captured;
        expect(captured, hasLength(1));
        final updated = (captured.single
            as BoardPanelInstance Function(BoardPanelInstance))(sourcePanel);
        expect(updated.state['remaining'], 0);
        expect(updated.state['isRunning'], isFalse);
        expect(updated.state['completed'], isTrue);
        expect(manager.isRunning('p1'), isFalse);
      });
    });
  });
}
