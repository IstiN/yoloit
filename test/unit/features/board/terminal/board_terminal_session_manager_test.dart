import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_history.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoxterm/xterm.dart';

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

  @override
  void appendOutputChunks(List<String> chunks) {
    appended.add(chunks.join());
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

  group('byte output path', () {
    test('batches byte chunks, flushes via writeBytes, decodes history once',
        () {
      fakeAsync((async) {
        final byteController = StreamController<Uint8List>();
        final stringController = StreamController<String>();
        final session = _FakeAgentSession(
          id: 'board_terminal_bytes',
          workspacePath: '/tmp',
        );
        final process = TerminalProcess(
          output: stringController.stream,
          outputBytes: byteController.stream,
          exitCode: Completer<int>().future,
        );

        BoardTerminalSessionManager.instance.attachProcessForTesting(
          process,
          session,
        );

        // The String channel must NOT be listened when bytes are available:
        // both wrap the same single-subscription native stream.
        expect(stringController.hasListener, isFalse);

        byteController.add(Uint8List.fromList(utf8.encode('a')));
        byteController.add(Uint8List.fromList(utf8.encode('b')));
        byteController.add(Uint8List.fromList(utf8.encode('c')));

        // Nothing is flushed before the batch window closes.
        expect(session.appended, isEmpty);
        expect(session.terminal.buffer.lines[0].toString(), isEmpty);
        async.elapse(const Duration(milliseconds: 49));
        expect(session.appended, isEmpty);

        async.elapse(const Duration(milliseconds: 1));
        // History receives the single decode of the concatenated flush —
        // the same text the String path would have produced.
        expect(session.appended, ['abc']);
        expect(session.terminal.buffer.lines[0].toString(), 'abc');

        byteController.close();
        stringController.close();
        async.elapse(const Duration(seconds: 1));
        // No extra flush from onDone because the buffer was already empty.
        expect(session.appended.length, 1);
      });
    });

    test('flushes immediately when the byte batch reaches the limit', () {
      fakeAsync((async) {
        final byteController = StreamController<Uint8List>();
        final session = _FakeAgentSession(
          id: 'board_terminal_bytes_large',
          workspacePath: '/tmp',
        );
        final process = TerminalProcess(
          output: const Stream<String>.empty(),
          outputBytes: byteController.stream,
          exitCode: Completer<int>().future,
        );

        BoardTerminalSessionManager.instance.attachProcessForTesting(
          process,
          session,
        );

        byteController.add(Uint8List.fromList(List.filled(16384, 0x78)));
        async.flushMicrotasks();

        expect(session.appended, ['x' * 16384]);
        // The terminal state matches the String path on the same payload.
        final reference = Terminal(maxLines: 2000)..write('x' * 16384);
        expect(session.terminal.buffer.cursorX, reference.buffer.cursorX);
        expect(session.terminal.buffer.cursorY, reference.buffer.cursorY);

        byteController.close();
      });
    });

    test('multibyte UTF-8 split across byte chunks in one flush is stitched',
        () {
      fakeAsync((async) {
        final byteController = StreamController<Uint8List>();
        final session = _FakeAgentSession(
          id: 'board_terminal_bytes_split',
          workspacePath: '/tmp',
        );
        final process = TerminalProcess(
          output: const Stream<String>.empty(),
          outputBytes: byteController.stream,
          exitCode: Completer<int>().future,
        );

        BoardTerminalSessionManager.instance.attachProcessForTesting(
          process,
          session,
        );

        // 'é' = 0xC3 0xA9, split across two chunks inside one flush: the
        // concatenated decode stitches it for BOTH terminal and history.
        byteController.add(Uint8List.fromList([0x61, 0xC3])); // 'a' + lead
        byteController.add(Uint8List.fromList([0xA9, 0x62])); // tail + 'b'
        async.elapse(const Duration(milliseconds: 50));

        expect(session.terminal.buffer.lines[0].toString(), 'aéb');
        expect(session.appended, ['aéb']);

        byteController.close();
      });
    });

    test('multibyte UTF-8 split across flushes is stitched in the terminal',
        () {
      fakeAsync((async) {
        final byteController = StreamController<Uint8List>();
        final session = _FakeAgentSession(
          id: 'board_terminal_bytes_split_flush',
          workspacePath: '/tmp',
        );
        final process = TerminalProcess(
          output: const Stream<String>.empty(),
          outputBytes: byteController.stream,
          exitCode: Completer<int>().future,
        );

        BoardTerminalSessionManager.instance.attachProcessForTesting(
          process,
          session,
        );

        byteController.add(Uint8List.fromList([0x61, 0xC3])); // 'a' + lead
        async.elapse(const Duration(milliseconds: 50));
        byteController.add(Uint8List.fromList([0xA9, 0x62])); // tail + 'b'
        async.elapse(const Duration(milliseconds: 50));

        // writeBytes keeps decoder state across flushes, so the terminal
        // renders the character correctly...
        expect(session.terminal.buffer.lines[0].toString(), 'aéb');
        // ...while history decodes each flush on its own (allowMalformed),
        // recording the truncated lead byte as U+FFFD. Same trade-off the
        // old per-chunk decode had.
        expect(session.appended, ['a\uFFFD', '\uFFFDb']);

        byteController.close();
      });
    });
  });
}
