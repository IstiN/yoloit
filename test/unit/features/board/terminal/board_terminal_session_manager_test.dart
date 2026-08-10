import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

// ignore: must_be_immutable
class _FakeAgentSession extends AgentSession {
  _FakeAgentSession({
    required super.id,
    required super.workspacePath,
    super.customName,
  }) : super(type: AgentType.terminal);

  final List<String> appended = [];

  @override
  void appendOutput(String rawData) {
    appended.add(rawData);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
  });

  test('batches many small PTY chunks into a single terminal write', () {
    fakeAsync((async) {
      final controller = StreamController<String>();
      final session = _FakeAgentSession(
        id: 'board_terminal_test',
        workspacePath: '/tmp',
      );
      final process = TerminalProcess(
        output: controller.stream,
        exitCode: Completer<int>().future,
      );

      BoardTerminalSessionManager.instance.attachProcessForTesting(
        process,
        session,
      );

      controller.add('a');
      controller.add('b');
      controller.add('c');
      controller.add('d');

      // Nothing should be flushed immediately.
      expect(session.appended, isEmpty);

      // Advance just before the batch window.
      async.elapse(const Duration(milliseconds: 49));
      expect(session.appended, isEmpty);

      // Crossing the 50ms window flushes the accumulated buffer.
      async.elapse(const Duration(milliseconds: 1));
      expect(session.appended.length, 1);
      expect(session.appended, ['abcd']);

      controller.close();
      async.elapse(const Duration(seconds: 1));
      // No extra flush from onDone because the buffer was already empty.
      expect(session.appended.length, 1);
    });
  });

  test('flushes immediately for a chunk that reaches the batch limit', () {
    fakeAsync((async) {
      final controller = StreamController<String>();
      final session = _FakeAgentSession(
        id: 'board_terminal_test_large',
        workspacePath: '/tmp',
      );
      final process = TerminalProcess(
        output: controller.stream,
        exitCode: Completer<int>().future,
      );

      BoardTerminalSessionManager.instance.attachProcessForTesting(
        process,
        session,
      );

      expect(session.appended, isEmpty);

      controller.add('x' * 16384);
      async.flushMicrotasks();

      expect(session.appended.length, 1);
      expect(session.appended, ['x' * 16384]);

      controller.close();
    });
  });

  group('renameSession', () {
    test('trims and stores the custom name, notifies, persists history',
        () async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting(
        's1',
        _FakeAgentSession(id: 's1', workspacePath: '/tmp/ws'),
      );
      var notifications = 0;
      void listener() => notifications++;
      manager.addListener(listener);
      addTearDown(() => manager.removeListener(listener));

      await manager.renameSession('s1', '  Deploy logs  ');

      final renamed = manager.sessionFor('s1')!;
      expect(renamed.customName, 'Deploy logs');
      expect(renamed.displayName, 'Deploy logs');
      expect(notifications, greaterThan(0));

      final entries = await BoardTerminalSessionHistory.instance.loadAll();
      final entry = entries.singleWhere((e) => e.id == 's1');
      expect(entry.sessionName, 'Deploy logs');
      expect(entry.workingDir, '/tmp/ws');
    });

    test('blank name clears the custom name and records the default',
        () async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting(
        's2',
        _FakeAgentSession(
          id: 's2',
          workspacePath: '/tmp/ws',
          customName: 'Old name',
        ),
      );

      await manager.renameSession('s2', '   ');

      final renamed = manager.sessionFor('s2')!;
      expect(renamed.customName, isNull);
      expect(renamed.displayName, AgentType.terminal.displayName);

      final entries = await BoardTerminalSessionHistory.instance.loadAll();
      final entry = entries.singleWhere((e) => e.id == 's2');
      // History keeps the last known display name for continuity.
      expect(entry.sessionName, 'Old name');
    });

    test('ignores unknown session ids without touching history', () async {
      final manager = BoardTerminalSessionManager.instance;

      await manager.renameSession('missing', 'Name');

      expect(manager.sessionFor('missing'), isNull);
      expect(await BoardTerminalSessionHistory.instance.loadAll(), isEmpty);
    });
  });
}
