import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _panelFromFixture(String fixtureName) {
  final state = _loadFixture(fixtureName);
  return BoardPanelInstance(
    id: 'test-panel-timer',
    type: 'board.timer',
    title: 'Timer',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
    state: state,
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'test-panel-timer',
      type: 'board.timer',
      title: 'Timer',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      state: state,
    );

void main() {
  final handler = const TimerCliHandler();

  group('TimerCliHandler — metadata', () {
    test('typeId is board.timer', () {
      expect(handler.typeId, 'board.timer');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(['start', 'pause', 'resume', 'reset', 'status', 'set']),
      );
    });
  });

  group('TimerCliHandler — status action', () {
    test('status from idle returns correct fields', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('status', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['duration'], 1500);
      expect(r.data!['remaining'], 1500);
      expect(r.data!['isRunning'], isFalse);
      expect(r.data!['isPaused'], isFalse);
      expect(r.data!['label'], 'Pomodoro');
    });

    test('status from running shows remaining time', () async {
      final panel = _panelFromFixture('timer_running');
      final r = await handler.handleAction('status', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['remaining'], 847);
      expect(r.data!['isRunning'], isTrue);
    });

    test('status from paused shows paused state', () async {
      final panel = _panelFromFixture('timer_paused');
      final r = await handler.handleAction('status', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['remaining'], 612);
      expect(r.data!['isPaused'], isTrue);
      expect(r.data!['isRunning'], isFalse);
    });
  });

  group('TimerCliHandler — start action', () {
    test('start with custom duration sets duration and isRunning=true', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('start', {'duration': 300}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 300);
      expect(r.stateUpdate!['remaining'], 300);
      expect(r.stateUpdate!['isRunning'], isTrue);
      expect(r.stateUpdate!['isPaused'], isFalse);
    });

    test('start without args uses existing duration', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('start', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 1500);
      expect(r.stateUpdate!['isRunning'], isTrue);
    });

    test('start with label sets label', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('start', {'duration': 600, 'label': 'Work'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['label'], 'Work');
    });

    test('start sets lastTick timestamp', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('start', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['lastTick'], isA<int>());
    });
  });

  group('TimerCliHandler — pause action', () {
    test('pause when running sets isRunning=false and isPaused=true', () async {
      final panel = _panelFromFixture('timer_running');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], isFalse);
      expect(r.stateUpdate!['isPaused'], isTrue);
    });

    test('pause when not running returns ok=false', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isFalse);
    });

    test('pause when already paused returns ok=false', () async {
      final panel = _panelFromFixture('timer_paused');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('TimerCliHandler — resume action', () {
    test('resume when paused sets isRunning=true and isPaused=false', () async {
      final panel = _panelFromFixture('timer_paused');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], isTrue);
      expect(r.stateUpdate!['isPaused'], isFalse);
    });

    test('resume sets lastTick timestamp', () async {
      final panel = _panelFromFixture('timer_paused');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['lastTick'], isA<int>());
    });

    test('resume when not paused returns ok=false', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isFalse);
    });

    test('resume when running (not paused) returns ok=false', () async {
      final panel = _panelFromFixture('timer_running');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('TimerCliHandler — reset action', () {
    test('reset resets remaining to duration and clears running state', () async {
      final panel = _panelFromFixture('timer_running');
      final r = await handler.handleAction('reset', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 1500);
      expect(r.stateUpdate!['isRunning'], isFalse);
      expect(r.stateUpdate!['isPaused'], isFalse);
    });

    test('reset from paused state resets correctly', () async {
      final panel = _panelFromFixture('timer_paused');
      final r = await handler.handleAction('reset', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 1500);
      expect(r.stateUpdate!['isRunning'], isFalse);
    });
  });

  group('TimerCliHandler — set action', () {
    test('set updates duration without starting', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('set', {'duration': 300}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 300);
      expect(r.stateUpdate!['isRunning'], isFalse);
    });

    test('set with label updates label', () async {
      final panel = _panelFromFixture('timer_idle');
      final r = await handler.handleAction('set', {'duration': 300, 'label': 'Quick break'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['label'], 'Quick break');
    });

    test('set resets remaining to new duration', () async {
      final panel = _panelFromFixture('timer_running');
      final r = await handler.handleAction('set', {'duration': 600}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 600);
    });
  });

  group('TimerCliHandler — unknown action', () {
    test('unknown action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('skip', {}, panel);
      expect(r.ok, isFalse);
    });
  });
}
