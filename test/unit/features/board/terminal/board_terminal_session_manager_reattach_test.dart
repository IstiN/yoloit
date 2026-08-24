// Regression test for the double-output bug seen as "kkii" when typing "ki".
//
// Root cause (proven by debug instrumentation: two `spawned` log lines and
// two `[rt-stream] seq=N` deliveries for the same sessionId):
// BoardTerminalSessionManager._spawn cancels the previous output
// subscription at the START (line ~163) but attaches the new one at the END
// (after `await launch`). Two concurrent spawns for the same sessionId
// interleave as: spawnA.cancel → spawnA.launch(await) → spawnB.cancel(none)
// → spawnB.launch(await) → spawnA.attach(subA) → spawnB.attach(subB). The
// second attach overwrites the map entry without cancelling subA, so BOTH
// subscriptions stay live and every PTY chunk reaches the terminal twice.
//
// Fix: _attachProcess must cancel any existing subscription for the
// sessionId before registering the new one (idempotent attach), and the
// spawn path must be serialized per sessionId so a second ensureSession
// shares the in-flight spawn instead of racing it.

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';

class _RecordingSession extends AgentSession {
  _RecordingSession(String id)
      : super(id: id, type: AgentType.terminal, workspacePath: '/tmp');

  final List<String> appended = [];

  @override
  void appendOutput(String rawData) => appended.add(rawData);
  @override
  void appendOutputChunks(List<String> chunks) =>
      appended.add(chunks.join());
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(
    () => BoardTerminalSessionManager.instance.clearSessionsForTesting(),
  );

  test(
    're-attaching a process for the same session cancels the previous '
    'output subscription (no double delivery)',
    () {
      fakeAsync((async) {
        final manager = BoardTerminalSessionManager.instance;
        final session = _RecordingSession('dup-attach');

        // First process/stream.
        final controller1 = StreamController<String>();
        final process1 = TerminalProcess(
          output: controller1.stream,
          exitCode: Completer<int>().future,
        );
        manager.attachProcessForTesting(process1, session);

        // A racing second spawn attaches a second process for the same
        // session BEFORE the first subscription was cancelled.
        final controller2 = StreamController<String>();
        final process2 = TerminalProcess(
          output: controller2.stream,
          exitCode: Completer<int>().future,
        );
        manager.attachProcessForTesting(process2, session);

        // Data arriving on the OLD stream must NOT reach the terminal
        // anymore — its subscription was cancelled by the re-attach.
        controller1.add('a');
        controller2.add('b');
        async.elapse(const Duration(milliseconds: 60));
        async.flushMicrotasks();

        expect(
          session.terminal.buffer.lines[0].toString(),
          'b',
          reason: 'only the latest attachment may deliver output; '
              'old subscription must be cancelled. Buffer: '
              '${session.terminal.buffer.lines[0]}',
        );
        expect(session.appended, ['b']);
      });
    },
  );
}