import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.timer',
      title: 'Timer',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 320),
      state: state,
    );

void main() {
  final handler = const TimerCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.timer');
  });

  test('supportedActions contains expected actions', () {
    expect(
      handler.supportedActions,
      containsAll(['start', 'pause', 'resume', 'reset', 'status', 'set']),
    );
  });

  group('getContent', () {
    test('returns correct structure with defaults', () {
      final content = handler.getContent(_panel());
      expect(content['duration'], 300);
      expect(content['remaining'], 300);
      expect(content['isRunning'], false);
      expect(content['isPaused'], false);
      expect(content['completed'], false);
      expect(content['label'], '');
    });

    test('returns custom state values', () {
      final content = handler.getContent(_panel(state: {
        'duration': 600,
        'remaining': 120,
        'isRunning': true,
        'label': 'Pomodoro',
      }));
      expect(content['duration'], 600);
      expect(content['remaining'], 120);
      expect(content['isRunning'], true);
      expect(content['label'], 'Pomodoro');
    });
  });

  group('handleAction', () {
    test('status returns current timer state', () async {
      final r = await handler.handleAction('status', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.data!['duration'], 300);
      expect(r.data!['remaining'], 300);
    });

    test('start creates running timer with default duration', () async {
      final r = await handler.handleAction('start', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], true);
      expect(r.stateUpdate!['remaining'], 300);
      expect(r.stateUpdate!['duration'], 300);
      expect(r.stateUpdate!['isPaused'], false);
      expect(r.stateUpdate!['completed'], false);
    });

    test('start with custom duration', () async {
      final r = await handler.handleAction('start', {'duration': 600}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 600);
      expect(r.stateUpdate!['remaining'], 600);
      expect(r.stateUpdate!['isRunning'], true);
    });

    test('start with label', () async {
      final r = await handler.handleAction(
        'start',
        {'label': 'My Timer'},
        _panel(),
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['label'], 'My Timer');
    });

    test('pause returns error when timer not running', () async {
      final r = await handler.handleAction('pause', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('not running'));
    });

    test('pause succeeds when timer is running', () async {
      final startResult = await handler.handleAction('start', {}, _panel());
      final state = startResult.stateUpdate!;

      final r = await handler.handleAction(
        'pause',
        {},
        _panel(state: state),
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], false);
      expect(r.stateUpdate!['isPaused'], true);
    });

    test('resume returns error when timer not paused', () async {
      final r = await handler.handleAction('resume', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('not paused'));
    });

    test('resume succeeds when timer is paused', () async {
      final startResult = await handler.handleAction('start', {}, _panel());
      final running = startResult.stateUpdate!;

      final pauseResult = await handler.handleAction(
        'pause',
        {},
        _panel(state: running),
      );
      final paused = pauseResult.stateUpdate!;

      final r = await handler.handleAction(
        'resume',
        {},
        _panel(state: {...running, ...paused}),
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], true);
      expect(r.stateUpdate!['isPaused'], false);
    });

    test('reset restores timer to full duration', () async {
      final r = await handler.handleAction(
        'reset',
        {},
        _panel(state: {
          'duration': 300,
          'remaining': 45,
          'isRunning': true,
          'completed': false,
        }),
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 300);
      expect(r.stateUpdate!['isRunning'], false);
      expect(r.stateUpdate!['isPaused'], false);
      expect(r.stateUpdate!['completed'], false);
    });

    test('set changes duration without starting', () async {
      final r = await handler.handleAction('set', {'duration': 900}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 900);
      expect(r.stateUpdate!['remaining'], 900);
      expect(r.stateUpdate!['isRunning'], false);
    });

    test('set with label', () async {
      final r = await handler.handleAction(
        'set',
        {'label': 'Work'},
        _panel(),
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['label'], 'Work');
    });

    test('unknown action returns error', () async {
      final r = await handler.handleAction('unknown', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Unknown'));
    });

    test('actionHelp contains all actions', () {
      final help = handler.actionHelp;
      for (final action in handler.supportedActions) {
        expect(help.containsKey(action), isTrue,
            reason: 'Missing help for action: $action');
      }
    });
  });
}
