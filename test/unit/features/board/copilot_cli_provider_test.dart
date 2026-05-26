import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/copilot_cli_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class _FakeProcess implements Process {
  _FakeProcess({required this.pid, required IOSink stdin})
    : _stdin = stdin,
      _exitCode = Completer<int>();

  final Completer<int> _exitCode;
  final StreamController<List<int>> _stdout = StreamController<List<int>>();
  final StreamController<List<int>> _stderr = StreamController<List<int>>();
  final IOSink _stdin;

  @override
  final int pid;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdout.stream;

  @override
  Stream<List<int>> get stderr => _stderr.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  void addStdout(String text) => _stdout.add(utf8.encode(text));

  void addStderr(String text) => _stderr.add(utf8.encode(text));

  Future<void> closeStdout() => _stdout.close();

  Future<void> closeStderr() => _stderr.close();

  void completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
  }

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    completeExit(-1);
    unawaited(_stdout.close());
    unawaited(_stderr.close());
    return true;
  }
}

class _ProcessStartCall {
  const _ProcessStartCall(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

class _FakeProcessStarter {
  final List<_FakeProcess> queuedProcesses = [];
  final List<_ProcessStartCall> calls = [];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add(_ProcessStartCall(executable, List<String>.from(arguments)));
    return queuedProcesses.removeAt(0);
  }
}

void main() {
  late Directory tempDir;
  late Directory sessionStateRoot;
  late File stdinSinkFile;
  late IOSink stdinSink;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('copilot-provider-test-');
    sessionStateRoot = Directory('${tempDir.path}/.copilot/session-state')
      ..createSync(recursive: true);
    stdinSinkFile = File('${tempDir.path}/stdin.txt');
    stdinSink = stdinSinkFile.openWrite();
  });

  tearDown(() async {
    await stdinSink.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  ChatSessionConfig _config() => ChatSessionConfig(
    sessionName: 'Hello',
    workingDir: tempDir.path,
    provider: 'copilot',
    model: 'gpt-5-mini',
  );

  group('CopilotCliProvider helpers', () {
    test('extracts matching session ids from multisession error', () {
      final ids = extractCopilotMultiSessionIds('''
Error: Multiple sessions match the name 'Hello'.

Matching sessions:
  4d638432-aa5e-4166-9ff8-5c5e8cd7f086
  c72854fb-2e31-4b7b-b820-727f0ccc4faa
''');

      expect(ids, [
        '4d638432-aa5e-4166-9ff8-5c5e8cd7f086',
        'c72854fb-2e31-4b7b-b820-727f0ccc4faa',
      ]);
    });

    test('picks the most recently modified matching session id', () async {
      final olderId = 'c72854fb-2e31-4b7b-b820-727f0ccc4faa';
      final newerId = '4d638432-aa5e-4166-9ff8-5c5e8cd7f086';
      final olderDir = Directory('${sessionStateRoot.path}/$olderId')
        ..createSync(recursive: true);
      final newerDir = Directory('${sessionStateRoot.path}/$newerId')
        ..createSync(recursive: true);
      final olderFile = File('${olderDir.path}/session.db')
        ..writeAsStringSync('');
      await Future<void>.delayed(const Duration(milliseconds: 1100));
      final newerFile = File('${newerDir.path}/session.db')
        ..writeAsStringSync('');
      final now = DateTime.now();
      olderFile.setLastModifiedSync(now.subtract(const Duration(days: 1)));
      newerFile.setLastModifiedSync(now);
      final recoveredId = pickMostRecentCopilotSessionId([
        newerId,
        olderId,
      ], sessionStateRoot: sessionStateRoot.path);

      expect(
        pickMostRecentCopilotSessionId([
          olderId,
          newerId,
        ], sessionStateRoot: sessionStateRoot.path),
        newerId,
      );
    });

    test(
      'falls back to the last listed session id when metadata is missing',
      () {
        final olderId = 'c72854fb-2e31-4b7b-b820-727f0ccc4faa';
        final newerId = '4d638432-aa5e-4166-9ff8-5c5e8cd7f086';

        expect(
          pickMostRecentCopilotSessionId([
            olderId,
            newerId,
          ], sessionStateRoot: sessionStateRoot.path),
          newerId,
        );
      },
    );
  });

  group('CopilotCliProvider recovery', () {
    test(
      'captures session id even when stdout finishes after exit code',
      () async {
        final starter = _FakeProcessStarter();
        final process = _FakeProcess(pid: 101, stdin: stdinSink);
        starter.queuedProcesses.add(process);
        final provider = CopilotCliProvider(
          processStarter: starter.start,
          homeDirectory: tempDir.path,
          sessionStateRoot: sessionStateRoot.path,
          enableSubAgentWatcher: false,
        );
        addTearDown(provider.dispose);

        final done = Completer<void>();
        provider
            .sendMessage(
              message: 'Hello',
              config: _config(),
              isFirstMessage: true,
            )
            .listen(null, onDone: () => done.complete());

        process.completeExit(0);
        process.addStdout(
          '{"type":"result","sessionId":"4d638432-aa5e-4166-9ff8-5c5e8cd7f086","exitCode":0}\n',
        );
        await process.closeStdout();
        await process.closeStderr();
        await done.future;

        expect(
          provider.getSessionId('Hello'),
          '4d638432-aa5e-4166-9ff8-5c5e8cd7f086',
        );
        expect(
          starter.calls.single.arguments,
          containsAll(['--name', 'Hello']),
        );
      },
    );

    test(
      'recovers ambiguous resume by retrying with latest session id',
      () async {
        final olderId = 'c72854fb-2e31-4b7b-b820-727f0ccc4faa';
        final newerId = '4d638432-aa5e-4166-9ff8-5c5e8cd7f086';
        final olderDir = Directory('${sessionStateRoot.path}/$olderId')
          ..createSync(recursive: true);
        final newerDir = Directory('${sessionStateRoot.path}/$newerId')
          ..createSync(recursive: true);
        final olderFile = File('${olderDir.path}/session.db')
          ..writeAsStringSync('');
        final newerFile = File('${newerDir.path}/session.db')
          ..writeAsStringSync('');
        final now = DateTime.now();
        olderFile.setLastModifiedSync(now.subtract(const Duration(days: 1)));
        newerFile.setLastModifiedSync(now);
        final recoveredId = pickMostRecentCopilotSessionId([
          newerId,
          olderId,
        ], sessionStateRoot: sessionStateRoot.path);

        final starter = _FakeProcessStarter();
        final failedProcess = _FakeProcess(pid: 201, stdin: stdinSink);
        final recoveredProcess = _FakeProcess(pid: 202, stdin: stdinSink);
        starter.queuedProcesses
          ..add(failedProcess)
          ..add(recoveredProcess);

        final provider = CopilotCliProvider(
          processStarter: starter.start,
          homeDirectory: tempDir.path,
          sessionStateRoot: sessionStateRoot.path,
          enableSubAgentWatcher: false,
        );
        addTearDown(provider.dispose);
        provider.setSessionId('Hello', 'Hello');

        final events = <ChatEvent>[];
        final done = Completer<void>();
        provider
            .sendMessage(
              message: 'как дела?',
              config: _config(),
              isFirstMessage: false,
            )
            .listen(events.add, onDone: () => done.complete());

        failedProcess.addStderr('''
Error: Multiple sessions match the name 'Hello'.

Matching sessions:
  $newerId
  $olderId

Specify the session ID directly: copilot --resume=<id>
''');
        failedProcess.completeExit(1);
        await failedProcess.closeStdout();
        await failedProcess.closeStderr();

        recoveredProcess.addStdout(
          '{"type":"assistant.message","id":"msg-1","data":{"content":"Привет"}}\n',
        );
        recoveredProcess.addStdout(
          '{"type":"result","sessionId":"$recoveredId","exitCode":0}\n',
        );
        recoveredProcess.completeExit(0);
        await recoveredProcess.closeStdout();
        await recoveredProcess.closeStderr();
        await done.future;

        expect(starter.calls, hasLength(2));
        expect(
          starter.calls.first.arguments,
          containsAll(['--resume', 'Hello']),
        );
        expect(
          starter.calls.last.arguments,
          containsAll(['--resume', recoveredId]),
        );
        expect(provider.getSessionId('Hello'), recoveredId);
        expect(events.map((e) => e.type), contains(ChatEventType.result));
      },
    );

    test('does not retry forever if recovered resume also fails', () async {
      final olderId = 'c72854fb-2e31-4b7b-b820-727f0ccc4faa';
      final newerId = '4d638432-aa5e-4166-9ff8-5c5e8cd7f086';
      final newerDir = Directory('${sessionStateRoot.path}/$newerId')
        ..createSync(recursive: true);
      final newerFile = File('${newerDir.path}/session.db')
        ..writeAsStringSync('');
      newerFile.setLastModifiedSync(DateTime.now());
      final recoveredId = pickMostRecentCopilotSessionId([
        olderId,
        newerId,
      ], sessionStateRoot: sessionStateRoot.path);

      final starter = _FakeProcessStarter();
      final failedProcess = _FakeProcess(pid: 301, stdin: stdinSink);
      final retriedProcess = _FakeProcess(pid: 302, stdin: stdinSink);
      starter.queuedProcesses
        ..add(failedProcess)
        ..add(retriedProcess);

      final provider = CopilotCliProvider(
        processStarter: starter.start,
        homeDirectory: tempDir.path,
        sessionStateRoot: sessionStateRoot.path,
        enableSubAgentWatcher: false,
      );
      addTearDown(provider.dispose);

      Object? capturedError;
      final done = Completer<void>();
      provider
          .sendMessage(
            message: 'как дела?',
            config: _config(),
            isFirstMessage: false,
          )
          .listen(
            (_) {},
            onError: (Object error) => capturedError = error,
            onDone: () => done.complete(),
          );

      failedProcess.addStderr('''
Error: Multiple sessions match the name 'Hello'.

Matching sessions:
  $olderId
  $newerId

Specify the session ID directly: copilot --resume=<id>
''');
      failedProcess.completeExit(1);
      await failedProcess.closeStdout();
      await failedProcess.closeStderr();

      retriedProcess.addStderr('still broken');
      retriedProcess.completeExit(1);
      await retriedProcess.closeStdout();
      await retriedProcess.closeStderr();
      await done.future;

      expect(starter.calls, hasLength(2));
      expect(
        starter.calls.last.arguments,
        containsAll(['--resume', recoveredId]),
      );
      expect(capturedError, 'still broken');
    });
  });
}
