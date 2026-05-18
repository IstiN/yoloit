import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/timer_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _timerPanel(Map<String, dynamic> state) => BoardPanelInstance(
      id: 'timer-panel-1',
      type: 'board.timer',
      title: 'Pomodoro Timer',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      state: state,
    );

BoardPanelInstance _timerFromFixture(String fixtureName) =>
    _timerPanel(_loadFixture(fixtureName));

void main() {
  final handler = const TimerCliHandler();

  group('Timer workflow — user runs a Pomodoro timer', () {
    test('status shows idle state correctly', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction('status', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['isRunning'], isFalse);
      expect(r.data!['isPaused'], isFalse);
      expect(r.data!['remaining'], 1500);
      expect(r.data!['label'], 'Pomodoro');
    });

    test('start from idle begins timer', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction('start', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], isTrue);
      expect(r.stateUpdate!['remaining'], 1500);
    });

    test('pause from running state pauses timer', () async {
      final panel = _timerFromFixture('timer_running');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isPaused'], isTrue);
      expect(r.stateUpdate!['isRunning'], isFalse);
    });

    test('resume from paused state resumes timer', () async {
      final panel = _timerFromFixture('timer_paused');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['isRunning'], isTrue);
      expect(r.stateUpdate!['isPaused'], isFalse);
    });

    test('reset restores full duration', () async {
      final panel = _timerFromFixture('timer_running');
      final r = await handler.handleAction('reset', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 1500);
      expect(r.stateUpdate!['isRunning'], isFalse);
      expect(r.stateUpdate!['isPaused'], isFalse);
    });

    test('set duration=300 label="Quick break" updates without starting', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction(
        'set',
        {'duration': 300, 'label': 'Quick break'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 300);
      expect(r.stateUpdate!['label'], 'Quick break');
      expect(r.stateUpdate!['isRunning'], isFalse);
    });

    test('full Pomodoro workflow — start → pause → resume → reset', () async {
      var panel = _timerFromFixture('timer_idle');

      // Start the timer
      final startResult = await handler.handleAction('start', {}, panel);
      expect(startResult.ok, isTrue);
      panel = _timerPanel({...panel.state, ...startResult.stateUpdate!});
      expect(panel.state['isRunning'], isTrue);

      // Pause the running timer
      final pauseResult = await handler.handleAction('pause', {}, panel);
      expect(pauseResult.ok, isTrue);
      panel = _timerPanel({...panel.state, ...pauseResult.stateUpdate!});
      expect(panel.state['isPaused'], isTrue);

      // Resume from paused
      final resumeResult = await handler.handleAction('resume', {}, panel);
      expect(resumeResult.ok, isTrue);
      panel = _timerPanel({...panel.state, ...resumeResult.stateUpdate!});
      expect(panel.state['isRunning'], isTrue);
      expect(panel.state['isPaused'], isFalse);

      // Reset the timer
      final resetResult = await handler.handleAction('reset', {}, panel);
      expect(resetResult.ok, isTrue);
      final finalState = {
        ...panel.state,
        ...resetResult.stateUpdate!,
      };
      expect(finalState['remaining'], 1500);
      expect(finalState['isRunning'], isFalse);
    });
  });

  group('Timer workflow — error states', () {
    test('pause when idle returns ok=false', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isFalse);
    });

    test('pause when already paused returns ok=false', () async {
      final panel = _timerFromFixture('timer_paused');
      final r = await handler.handleAction('pause', {}, panel);
      expect(r.ok, isFalse);
    });

    test('resume when idle returns ok=false', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isFalse);
    });

    test('resume when running (not paused) returns ok=false', () async {
      final panel = _timerFromFixture('timer_running');
      final r = await handler.handleAction('resume', {}, panel);
      expect(r.ok, isFalse);
    });

    test('cannot double-start (start resets running timer)', () async {
      // Start returns ok=true even on running state (it restarts from full duration)
      final panel = _timerFromFixture('timer_running');
      final r = await handler.handleAction('start', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['remaining'], 1500); // reset to full
    });
  });

  group('Timer workflow — set action variations', () {
    test('set duration without label keeps existing label', () async {
      final panel = _timerFromFixture('timer_idle');
      final r = await handler.handleAction('set', {'duration': 600}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['duration'], 600);
      expect(r.stateUpdate!.containsKey('label'), isFalse);
    });

    test('set → start workflow uses new duration', () async {
      var panel = _timerFromFixture('timer_idle');

      // Set a short duration
      final setResult = await handler.handleAction('set', {'duration': 300}, panel);
      expect(setResult.ok, isTrue);
      panel = _timerPanel({...panel.state, ...setResult.stateUpdate!});

      // Start uses the new duration
      final startResult = await handler.handleAction('start', {}, panel);
      expect(startResult.ok, isTrue);
      expect(startResult.stateUpdate!['duration'], 300);
      expect(startResult.stateUpdate!['remaining'], 300);
    });
  });
}
