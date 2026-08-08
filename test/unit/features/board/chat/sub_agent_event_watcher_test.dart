import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/sub_agent_event_watcher.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Waits until [condition] holds, polling every 50 ms.
Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      fail('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  group('SubAgentEventWatcher', () {
    const pid = 424242;
    late Directory homeDir;
    late Directory sessionDir;
    late File eventsFile;
    late SubAgentEventWatcher watcher;
    late List<ChatEvent> events;
    late StreamSubscription<ChatEvent> sub;

    Future<void> appendLine(String line) async {
      await eventsFile.writeAsString(
        '$line\n',
        mode: FileMode.append,
        flush: true,
      );
    }

    /// The watcher seeks to the end of events.jsonl when it opens it, so
    /// lines appended before discovery are skipped. Probe repeatedly until
    /// one line is observed — that proves the file is being tailed.
    Future<void> probeUntilTailing() async {
      final sw = Stopwatch()..start();
      while (sw.elapsed < const Duration(seconds: 15)) {
        await appendLine('{"type":"subagent.started","data":{"probe":true}}');
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (events.any((e) => e.data['probe'] == true)) return;
      }
      fail('Watcher never started tailing events.jsonl');
    }

    List<ChatEvent> realEvents() =>
        events.where((e) => e.data['probe'] != true).toList();

    setUp(() {
      homeDir = Directory.systemTemp.createTempSync('subagent_watcher_test');
      sessionDir = Directory(
        '${homeDir.path}/.copilot/session-state/session-1',
      )..createSync(recursive: true);
      File('${sessionDir.path}/inuse.$pid.lock').writeAsStringSync('locked');
      eventsFile = File('${sessionDir.path}/events.jsonl')
        ..writeAsStringSync('');

      watcher = SubAgentEventWatcher(pid: pid, homeDir: homeDir.path);
      events = <ChatEvent>[];
      sub = watcher.events.listen(events.add);
    });

    tearDown(() async {
      await sub.cancel();
      await watcher.dispose();
      if (homeDir.existsSync()) {
        homeDir.deleteSync(recursive: true);
      }
    });

    test(
      'discovers session via lock file and maps every sub-agent event type',
      () async {
        // A session locked by a *different* pid must be ignored.
        final otherDir = Directory(
          '${homeDir.path}/.copilot/session-state/session-other',
        )..createSync(recursive: true);
        File('${otherDir.path}/inuse.999.lock').writeAsStringSync('locked');

        // Pre-existing content is skipped (watcher seeks to end on open).
        await appendLine('{"type":"subagent.started","data":{"old":true}}');

        await probeUntilTailing();

        await appendLine(
          '{"type":"subagent.started","id":"e1","parentId":"p0",'
          '"agentId":"agent-1","timestamp":"2024-01-02T03:04:05.000Z",'
          '"data":{"foo":"bar"}}',
        );
        await appendLine(
          '{"type":"subagent.completed","agentId":"agent-1","data":{}}',
        );
        await appendLine(
          '{"type":"tool.execution_start",'
          '"data":{"parentToolCallId":"ptc-1","toolCallId":"tc-1"}}',
        );
        // No parentToolCallId → not a sub-agent tool call, dropped.
        await appendLine(
          '{"type":"tool.execution_start","data":{"toolCallId":"tc-2"}}',
        );
        await appendLine(
          '{"type":"tool.execution_complete",'
          '"data":{"parentToolCallId":"ptc-1","success":true}}',
        );
        // No parentToolCallId → dropped.
        await appendLine('{"type":"tool.execution_complete","data":{}}');
        await appendLine(
          '{"type":"assistant.message","agentId":"agent-1",'
          '"data":{"content":"hello from sub-agent"}}',
        );
        // assistant.message without agentId is the main agent → dropped.
        await appendLine(
          '{"type":"assistant.message","data":{"content":"main agent"}}',
        );
        // Unknown type → dropped.
        await appendLine('{"type":"session.idle","data":{}}');
        // Malformed JSON → skipped by the parser.
        await appendLine('this is not json');
        // Empty line → skipped.
        await appendLine('');

        await _waitFor(
          () => realEvents().any(
            (e) => e.type == ChatEventType.subagentMessage,
          ),
        );

        final mapped = realEvents();
        expect(mapped, hasLength(5));

        final started = mapped[0];
        expect(started.type, ChatEventType.subagentStarted);
        expect(started.rawType, 'subagent.started');
        expect(started.id, 'e1');
        expect(started.parentId, 'p0');
        expect(started.data['foo'], 'bar');
        // agentId from the top-level JSON is merged into data.
        expect(started.data['agentId'], 'agent-1');
        expect(started.timestamp, DateTime.parse('2024-01-02T03:04:05.000Z'));

        final completed = mapped[1];
        expect(completed.type, ChatEventType.subagentCompleted);
        expect(completed.rawType, 'subagent.completed');

        final toolStart = mapped[2];
        expect(toolStart.type, ChatEventType.subagentToolStart);
        expect(toolStart.data['toolCallId'], 'tc-1');

        final toolComplete = mapped[3];
        expect(toolComplete.type, ChatEventType.subagentToolComplete);
        expect(toolComplete.data['success'], isTrue);

        final message = mapped[4];
        expect(message.type, ChatEventType.subagentMessage);
        expect(message.data['content'], 'hello from sub-agent');

        // Dropped / skipped lines never produce events.
        expect(mapped.any((e) => e.data['old'] == true), isFalse);
        expect(mapped.any((e) => e.data['toolCallId'] == 'tc-2'), isFalse);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test('handles events with missing data and agentId fields', () async {
      await probeUntilTailing();

      // No "data" key at all → falls back to an empty map.
      await appendLine('{"type":"subagent.completed"}');

      await _waitFor(
        () => realEvents().any(
          (e) => e.type == ChatEventType.subagentCompleted,
        ),
      );

      final completed = realEvents().first;
      expect(completed.type, ChatEventType.subagentCompleted);
      expect(completed.data, isEmpty);
      expect(completed.id, isNull);
      expect(completed.timestamp, isNull);
      expect(completed.parentId, isNull);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('buffers an incomplete line until the newline arrives', () async {
      await probeUntilTailing();

      // First chunk: no trailing newline → stays in the line buffer.
      await eventsFile.writeAsString(
        '{"type":"subagent.completed","agentId":"a2","data":{"par',
        mode: FileMode.append,
        flush: true,
      );
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(
        realEvents().where(
          (e) => e.type == ChatEventType.subagentCompleted,
        ),
        isEmpty,
      );

      // Second chunk completes the line.
      await eventsFile.writeAsString(
        'tial":true}}\n',
        mode: FileMode.append,
        flush: true,
      );

      await _waitFor(
        () => realEvents().any((e) => e.data['partial'] == true),
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('emits nothing when the session-state dir does not exist', () async {
      await sub.cancel();
      await watcher.dispose();
      homeDir.deleteSync(recursive: true);

      homeDir = Directory.systemTemp.createTempSync(
        'subagent_watcher_empty_home',
      );
      watcher = SubAgentEventWatcher(pid: pid, homeDir: homeDir.path);
      events = <ChatEvent>[];
      sub = watcher.events.listen(events.add);

      // Polling loop lists a missing directory every 400 ms and must not
      // crash or emit anything.
      await Future<void>.delayed(const Duration(seconds: 1));
      expect(events, isEmpty);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}
