import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
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
  });
}
