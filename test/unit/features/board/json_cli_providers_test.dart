import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/codex_cli_provider.dart';
import 'package:yoloit/features/board/chat/kimi_cli_provider.dart';
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

class _TrackingIOSink implements IOSink {
  bool closed = false;

  @override
  Future<void> close() {
    closed = true;
    return Future<void>.value();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStarter {
  final processes = <_FakeProcess>[];
  final calls = <List<String>>[];

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    calls.add([executable, ...arguments]);
    return processes.removeAt(0);
  }
}

void main() {
  late Directory tempDir;
  late _TrackingIOSink stdinSink;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = await Directory.systemTemp.createTemp('json-cli-provider-test-');
    stdinSink = _TrackingIOSink();
  });

  tearDown(() async {
    await stdinSink.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  ChatSessionConfig config(String provider) => ChatSessionConfig(
    sessionName: 'Smoke',
    workingDir: tempDir.path,
    provider: provider,
    model: 'model-id',
  );

  test('Codex fallback models mirror bundled CLI picker models', () {
    expect(kCodexModels.map((m) => m.id), [
      'gpt-5.5',
      'gpt-5.4',
      'gpt-5.4-mini',
      'gpt-5.3-codex',
      'gpt-5.2',
    ]);
    expect(kCodexModels.first.isDefault, isTrue);
  });

  test('Kimi provider parses assistant and session id JSONL', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 101, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'hello',
              config: config('kimi'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout('{"role":"assistant","content":"KIMI_OK"}\n');
    process.addStdout(
      '{"role":"meta","type":"session.resume_hint","session_id":"kimi-session"}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events.single.type, ChatEventType.assistantMessage);
    expect(events.single.messageContent, 'KIMI_OK');
    expect(provider.getSessionId('Smoke'), 'kimi-session');
    expect(stdinSink.closed, isTrue);
  });

  test('Kimi provider parses upstream assistant content parts', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 102, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'hello',
              config: config('kimi'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"role":"assistant","content":[{"type":"text","text":"KIMI_"},{"text":"PARTS"}]}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events.single.type, ChatEventType.assistantMessage);
    expect(events.single.messageContent, 'KIMI_PARTS');
    expect(stdinSink.closed, isTrue);
    expect(starter.calls.single, contains('--output-format'));
    expect(starter.calls.single, contains('stream-json'));
  });

  test('Codex provider parses thread, assistant, and usage JSONL', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 202, stdin: stdinSink);
    starter.processes.add(process);
    final provider = CodexCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'hello',
              config: config('codex'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout('{"type":"thread.started","thread_id":"codex-thread"}\n');
    process.addStdout(
      '{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"CODEX_OK"}}\n',
    );
    process.addStdout(
      '{"type":"turn.completed","usage":{"output_tokens":7}}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events.first.type, ChatEventType.assistantMessage);
    expect(events.first.messageContent, 'CODEX_OK');
    expect(events.last.type, ChatEventType.result);
    expect(events.last.usageData?['outputTokens'], 7);
    expect(provider.getSessionId('Smoke'), 'codex-thread');
    expect(stdinSink.closed, isTrue);
    expect(starter.calls.single.take(4), [
      'codex',
      'exec',
      '--json',
      '--skip-git-repo-check',
    ]);
  });
}
