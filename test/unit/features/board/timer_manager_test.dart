import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_manager.dart';

void main() {
  group('TimerManager', () {
    late TimerManager manager;

    setUp(() {
      manager = TimerManager.testInstance();
    });

    tearDown(() {
      manager.disposeAll();
    });

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
}
