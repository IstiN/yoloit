import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
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

  test('Codex fallback models mirror current CLI picker models', () {
    expect(kCodexModels.map((m) => m.id), ['gpt-5.5', 'gpt-5.4-mini']);
    expect(kCodexModels.first.isDefault, isTrue);
  });

  test('Kimi provider parses assistant and session id JSONL', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 101, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

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
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

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

  test('Kimi provider parses thinking content parts', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 102, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

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
      '{"role":"assistant","content":[{"type":"think","think":"Let me think..."},{"type":"text","text":"Result"}]}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events.single.type, ChatEventType.assistantMessage);
    expect(events.single.messageContent, contains('Let me think...'));
    expect(events.single.messageContent, contains('Result'));
    expect(stdinSink.closed, isTrue);
  });

  test('Kimi provider parses assistant with tool_calls', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 103, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

    final eventsFuture =
        provider
            .sendMessage(
              message: 'run ls',
              config: config('kimi'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"role":"assistant","content":"Sure.","tool_calls":[{"type":"function","id":"call_abc","function":{"name":"bash","arguments":"{\\"command\\": \\"ls\\"}"}}]}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(events[0].type, ChatEventType.toolStart);
    expect(events[0].data['toolCallId'], 'call_abc');
    expect(events[0].data['toolName'], 'bash');
    expect(events[1].type, ChatEventType.assistantMessage);
    expect(events[1].messageContent, 'Sure.');
    expect(events[1].toolRequests, hasLength(1));
    expect(events[1].toolRequests.first['toolCallId'], 'call_abc');
    expect(events[1].toolRequests.first['name'], 'bash');
  });

  test('Kimi provider parses tool result message', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 104, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

    final eventsFuture =
        provider
            .sendMessage(
              message: 'run ls',
              config: config('kimi'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"role":"tool","content":[{"type":"text","text":"file.txt"}],"tool_call_id":"call_abc"}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events.single.type, ChatEventType.toolComplete);
    expect(events.single.toolCallId, 'call_abc');
    expect(events.single.toolResultContent, 'file.txt');
    expect(events.single.toolSuccess, isTrue);
  });

  test('Kimi provider parses notification and plan display', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 105, stdin: stdinSink);
    starter.processes.add(process);
    final provider = KimiCliProvider(
      wireJsonlPath: '',
      processStarter: starter.start,
    );

    final eventsFuture =
        provider
            .sendMessage(
              message: 'plan',
              config: config('kimi'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"id":"n1","category":"system","type":"mcp_ready","source_kind":"system","source_id":"sys","title":"MCP ready","body":"Servers loaded","severity":"info","created_at":123.0,"payload":{}}\n',
    );
    process.addStdout(
      '{"content":"# Plan\\n1. A\\n2. B","file_path":"/tmp/plan.md"}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(events[0].type, ChatEventType.sessionStatus);
    expect(events[0].data['title'], 'MCP ready');
    expect(events[1].type, ChatEventType.assistantMessage);
    expect(events[1].messageContent, '# Plan\n1. A\n2. B');
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

  test('Codex provider resumes without unsupported cd arg', () async {
    final starter = _FakeStarter();
    final firstProcess = _FakeProcess(pid: 203, stdin: stdinSink);
    final secondStdinSink = _TrackingIOSink();
    addTearDown(secondStdinSink.close);
    final secondProcess = _FakeProcess(pid: 204, stdin: secondStdinSink);
    starter.processes.addAll([firstProcess, secondProcess]);
    final provider = CodexCliProvider(processStarter: starter.start);
    const runtimeContext = ChatRuntimeContext(
      boardId: 'board-1',
      boardName: 'TestBoard',
      panelId: 'chat-1',
      panelTitle: 'AI Chat',
    );

    final firstEventsFuture =
        provider
            .sendMessage(
              message: 'hello',
              config: config('codex'),
              isFirstMessage: true,
              runtimeContext: runtimeContext,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);
    firstProcess.addStdout(
      '{"type":"thread.started","thread_id":"codex-thread"}\n',
    );
    await firstProcess.closeStdout();
    await firstProcess.closeStderr();
    firstProcess.completeExit(0);
    await firstEventsFuture;

    final secondEventsFuture =
        provider
            .sendMessage(
              message: 'draw shapes on the board',
              config: config('codex'),
              isFirstMessage: false,
              runtimeContext: runtimeContext,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);
    secondProcess.addStdout(
      '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"OK"}}\n',
    );
    await secondProcess.closeStdout();
    await secondProcess.closeStderr();
    secondProcess.completeExit(0);
    await secondEventsFuture;

    expect(starter.calls, hasLength(2));
    expect(starter.calls.first, contains('--cd'));
    final resumeCall = starter.calls.last;
    expect(resumeCall.take(3), ['codex', 'exec', 'resume']);
    expect(resumeCall, isNot(contains('--cd')));
    expect(resumeCall, isNot(contains('-C')));
    expect(resumeCall, contains('codex-thread'));
    expect(resumeCall.last, contains('YoLoIT board reminder'));
    expect(resumeCall.last, contains('yoloit shape:create'));
    expect(resumeCall.last, contains('Current board: `TestBoard`'));
    expect(stdinSink.closed, isTrue);
    expect(secondStdinSink.closed, isTrue);
  });

  test('Codex provider parses command execution items', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 205, stdin: stdinSink);
    starter.processes.add(process);
    final provider = CodexCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'run ls',
              config: config('codex'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"type":"item.started","item":{"id":"cmd_1","type":"command_execution","command":"ls -la","aggregated_output":"","status":"in_progress"}}\n',
    );
    process.addStdout(
      '{"type":"item.completed","item":{"id":"cmd_1","type":"command_execution","command":"ls -la","aggregated_output":"total 0","exit_code":0,"status":"completed"}}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(events[0].type, ChatEventType.toolStart);
    expect(events[0].data['toolCallId'], 'cmd_1');
    expect(events[0].data['toolName'], 'ls -la');
    expect(events[1].type, ChatEventType.toolComplete);
    expect(events[1].data['toolCallId'], 'cmd_1');
    expect(events[1].toolResultContent, 'total 0');
    expect(events[1].toolSuccess, isTrue);
  });

  test('Codex provider parses MCP tool call items', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 206, stdin: stdinSink);
    starter.processes.add(process);
    final provider = CodexCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'search',
              config: config('codex'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"type":"item.started","item":{"id":"mcp_1","type":"mcp_tool_call","server":"filesystem","tool":"read_file","arguments":{"path":"/tmp/test.txt"},"status":"in_progress"}}\n',
    );
    process.addStdout(
      '{"type":"item.completed","item":{"id":"mcp_1","type":"mcp_tool_call","server":"filesystem","tool":"read_file","arguments":{"path":"/tmp/test.txt"},"result":{"content":[{"type":"text","text":"hello"}]},"status":"completed"}}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(events[0].type, ChatEventType.toolStart);
    expect(events[0].data['toolCallId'], 'mcp_1');
    expect(events[0].data['toolName'], 'filesystem/read_file');
    expect(events[1].type, ChatEventType.toolComplete);
    expect(events[1].data['toolCallId'], 'mcp_1');
    expect(events[1].toolResultContent, 'hello');
    expect(events[1].toolSuccess, isTrue);
  });

  test('Codex provider parses file change and reasoning items', () async {
    final starter = _FakeStarter();
    final process = _FakeProcess(pid: 207, stdin: stdinSink);
    starter.processes.add(process);
    final provider = CodexCliProvider(processStarter: starter.start);

    final eventsFuture =
        provider
            .sendMessage(
              message: 'refactor',
              config: config('codex'),
              isFirstMessage: true,
            )
            .toList();
    await Future<void>.delayed(Duration.zero);

    process.addStdout(
      '{"type":"item.completed","item":{"id":"reason_1","type":"reasoning","text":"Thinking..."}}\n',
    );
    process.addStdout(
      '{"type":"item.completed","item":{"id":"fc_1","type":"file_change","changes":[{"path":"lib/main.dart","kind":"update"}],"status":"completed"}}\n',
    );
    await process.closeStdout();
    await process.closeStderr();
    process.completeExit(0);

    final events = await eventsFuture;
    expect(events, hasLength(2));
    expect(events[0].type, ChatEventType.assistantMessage);
    expect(events[0].messageContent, 'Thinking...');
    expect(events[1].type, ChatEventType.assistantMessage);
    expect(events[1].messageContent, contains('File changes'));
    expect(events[1].messageContent, contains('lib/main.dart'));
  });
}
