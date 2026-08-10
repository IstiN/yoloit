import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/cursor_agent_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class _FakeProcess implements Process {
  _FakeProcess({
    required List<String> stdoutLines,
    List<String> stderrLines = const [],
    required int exitCode,
  })  : _stdout = StreamController<List<int>>(),
        _stderr = StreamController<List<int>>(),
        _exitCode = exitCode {
    _emit(stdoutLines, _stdout);
    _emit(stderrLines, _stderr);
  }

  final StreamController<List<int>> _stdout;
  final StreamController<List<int>> _stderr;
  final int _exitCode;

  static void _emit(List<String> lines, StreamController<List<int>> c) {
    Future.microtask(() async {
      for (final line in lines) {
        c.add(utf8.encode('$line\n'));
        await Future.delayed(const Duration(milliseconds: 5));
      }
      await c.close();
    });
  }

  @override
  Stream<List<int>> get stdout => _stdout.stream;
  @override
  Stream<List<int>> get stderr => _stderr.stream;
  @override
  IOSink get stdin => _FakeIOSink();
  @override
  Future<int> get exitCode async => _exitCode;
  @override
  int get pid => 42;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIOSink implements IOSink {
  @override
  Future close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProcessStarter _starterFor({
  List<String> stdout = const [],
  List<String> stderr = const [],
  int exitCode = 0,
}) {
  return (String exe, List<String> args,
          {String? workingDirectory,
          Map<String, String>? environment}) async =>
      _FakeProcess(
        stdoutLines: stdout,
        stderrLines: stderr,
        exitCode: exitCode,
      );
}

void main() {
  group('CursorAgentProvider', () {
    test('provider metadata', () {
      final p = CursorAgentProvider();
      expect(p.providerId, 'cursor');
      expect(p.displayName, 'Cursor Agent');
      expect(p.supportsImages, isTrue);
      expect(p.imageMode, ChatImageMode.filePath);
      expect(p.passSessionArgs, isFalse);
    });

    test('emits system event from init', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"system","subtype":"init","session_id":"sess-1"}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.first.type, ChatEventType.sessionStatus);
      expect(events.first.rawType, 'cursor.system.init');
      expect(p.getSessionId('s1'), 'sess-1');
    });

    test('emits assistant message from final event', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"assistant","message":{"content":[{"type":"text","text":"hello"}]}}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.first.type, ChatEventType.assistantMessage);
      expect(events.first.data['content'], 'hello');
    });

    test('emits delta events for streaming chunks', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"assistant","timestamp_ms":1,"message":{"content":[{"type":"text","text":"hel"}]}}',
          '{"type":"assistant","timestamp_ms":2,"message":{"content":[{"type":"text","text":"hello"}]}}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      // First event: assistantMessageStart + delta
      expect(events.first.type, ChatEventType.assistantMessageStart);
      expect(events[1].type, ChatEventType.assistantDelta);
      expect(events[1].data['deltaContent'], 'hel');
      // Second: just delta (new portion)
      expect(events[2].type, ChatEventType.assistantDelta);
      expect(events[2].data['deltaContent'], 'lo');
    });

    test('emits tool start and complete events', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"tool_call","subtype":"started","call_id":"tc-1","tool_call":{"shellToolCall":{"description":"Run shell","args":{"command":"ls"}}}}',
          '{"type":"tool_call","subtype":"completed","call_id":"tc-1","tool_call":{"shellToolCall":{"result":{"success":{"exitCode":0,"stdout":"file.txt"}}}}}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(events, hasLength(2));
      expect(events[0].type, ChatEventType.toolStart);
      expect(events[0].data['toolName'], 'Run shell');
      expect(events[1].type, ChatEventType.toolComplete);
      expect(events[1].data['success'], isTrue);
    });

    test('emits result event with usage', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"result","usage":{"outputTokens":42},"duration_ms":1500}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.first.type, ChatEventType.result);
      expect(events.first.data['usage']['outputTokens'], 42);
      expect(events.first.data['usage']['totalApiDurationMs'], 1500);
    });

    test('resumes with stored session id', () async {
      late List<String> capturedArgs;
      final p = CursorAgentProvider(
        processStarter: (String exe, List<String> args,
                {String? workingDirectory,
                Map<String, String>? environment}) {
          capturedArgs = args;
          return Future.value(_FakeProcess(
            stdoutLines: const ['{"type":"result"}'],
            exitCode: 0,
          ));
        },
      );

      p.setSessionId('s1', 'cursor-sess-123');
      p.sessionModels['s1'] = 'gpt-4';

      await p
          .sendMessage(
            message: 'continue',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
              model: 'gpt-4',
            ),
            isFirstMessage: false,
          )
          .toList();

      expect(capturedArgs, containsAll(['--resume', 'cursor-sess-123']));
    });

    test('clears session when model changes', () async {
      late List<String> capturedArgs;
      final p = CursorAgentProvider(
        processStarter: (String exe, List<String> args,
                {String? workingDirectory,
                Map<String, String>? environment}) {
          capturedArgs = args;
          return Future.value(_FakeProcess(
            stdoutLines: const ['{"type":"result"}'],
            exitCode: 0,
          ));
        },
      );

      p.setSessionId('s1', 'cursor-sess-123');
      p.sessionModels['s1'] = 'gpt-4';

      await p
          .sendMessage(
            message: 'continue',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
              model: 'claude-3', // different model
            ),
            isFirstMessage: false,
          )
          .toList();

      expect(capturedArgs, isNot(contains('--resume')));
      expect(p.getSessionId('s1'), isNull);
    });

    test('propagates stderr on error exit', () async {
      final p = CursorAgentProvider(
        processStarter: _starterFor(
          stderr: ['cursor-agent: command not found'],
          exitCode: 127,
        ),
      );

      final stream = p.sendMessage(
        message: 'x',
        config: const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
        ),
        isFirstMessage: true,
      );

      await expectLater(
        stream,
        emitsError(
          isA<Object>().having(
            (e) => e.toString(),
            'msg',
            'cursor-agent: command not found',
          ),
        ),
      );
    });
  });

  group('CursorAgentProvider._parseModelList', () {
    test('parses id - name lines and marks auto as default', () {
      final models = CursorAgentProvider.parseModelListForTest(
        'Available models:\n'
        'auto - Auto (recommended)\n'
        'gpt-5 - GPT-5\n'
        'claude-4-sonnet - Claude 4 Sonnet\n',
      );

      expect(models, hasLength(3));
      expect(models[0].id, 'auto');
      expect(models[0].displayName, 'Auto (recommended)');
      expect(models[0].isDefault, isTrue);
      expect(models[1].id, 'gpt-5');
      expect(models[1].displayName, 'GPT-5');
      expect(models[1].isDefault, isFalse);
      expect(models[2].id, 'claude-4-sonnet');
    });

    test('skips blank, header and malformed lines', () {
      final models = CursorAgentProvider.parseModelListForTest(
        '\n'
        'Available models\n'
        '   \n'
        'no-separator-line\n'
        'ok-model - Ok Model\n',
      );

      expect(models, hasLength(1));
      expect(models.single.id, 'ok-model');
      expect(models.single.displayName, 'Ok Model');
      expect(models.single.isDefault, isFalse);
    });

    test('keeps extra separators in the display name', () {
      final models = CursorAgentProvider.parseModelListForTest(
        'gpt-5 - GPT-5 - latest\n',
      );

      expect(models, hasLength(1));
      expect(models.single.id, 'gpt-5');
      expect(models.single.displayName, 'GPT-5 - latest');
    });

    test('returns an empty list for empty output', () {
      expect(CursorAgentProvider.parseModelListForTest(''), isEmpty);
      expect(CursorAgentProvider.parseModelListForTest('   \n  '), isEmpty);
    });
  });
}
