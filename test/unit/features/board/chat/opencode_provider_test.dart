import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/opencode_provider.dart';
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
  group('OpencodeProvider', () {
    test('provider metadata', () {
      final p = OpencodeProvider();
      expect(p.providerId, 'opencode');
      expect(p.displayName, 'OpenCode');
      expect(p.supportsImages, isTrue);
      expect(p.imageMode, ChatImageMode.filePath);
      expect(p.passSessionArgs, isFalse);
    });

    test('emits user message event first', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"text","part":{"text":"hello","id":"p1"}}',
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

      expect(events.first.type, ChatEventType.userMessage);
      expect(events.first.rawType, 'opencode.user.message');
    });

    test('emits assistant message from text event', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"text","part":{"text":"hello world","id":"p1"}}',
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

      // userMessage + assistantMessageStart + assistantMessage + result
      expect(events, hasLength(4));
      expect(events[1].type, ChatEventType.assistantMessageStart);
      expect(events[1].data['messageId'], 'p1');
      expect(events[2].type, ChatEventType.assistantMessage);
      expect(events[2].data['content'], 'hello world');
    });

    test('emits step start/finish events', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"step_start","part":{"name":"thinking"}}',
          '{"type":"step_finish","part":{"cost":0.001,"tokens":42,"reason":"done"}}',
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

      // userMessage + step_start + step_finish + result
      expect(events, hasLength(4));
      expect(events[1].type, ChatEventType.assistantTurnStart);
      expect(events[2].type, ChatEventType.assistantTurnEnd);
      expect(events[2].data['tokens'], 42);
    });

    test('emits tool use events', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"tool_use","part":{"callID":"tc-1","tool":"shell","state":{"status":"completed","input":{"command":"ls"},"output":"file.txt","title":"List files"}}}',
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

      // userMessage + toolStart + toolComplete + result
      expect(events, hasLength(4));
      expect(events[1].type, ChatEventType.toolStart);
      expect(events[1].data['toolName'], 'List files');
      expect(events[2].type, ChatEventType.toolComplete);
      expect(events[2].data['success'], isTrue);
    });

    test('emits reasoning delta events', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"reasoning","part":{"text":"thinking...","id":"r1"}}',
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

      // userMessage + assistantDelta + result
      expect(events, hasLength(3));
      expect(events[1].type, ChatEventType.assistantDelta);
      expect(events[1].data['deltaContent'], 'thinking...');
    });

    test('emits error event from error type', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"error","error":{"data":{"message":"something broke"}}}',
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

      // userMessage + assistantMessage (error) + result
      expect(events, hasLength(3));
      expect(events[1].type, ChatEventType.assistantMessage);
      expect(events[1].data['content'], contains('something broke'));
    });

    test('captures sessionID from first event', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"text","sessionID":"sess-abc","part":{"text":"hi","id":"p1"}}',
        ]),
      );

      await p
          .sendMessage(
            message: 'hello',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(p.getSessionId('s1'), 'sess-abc');
    });

    test('resumes with stored session id', () async {
      List<String>? capturedArgs;
      final p = OpencodeProvider(
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

      p.setSessionId('s1', 'sess-123');
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

      expect(capturedArgs, containsAll(['--session', 'sess-123']));
    });

    test('clears session when model changes', () async {
      List<String>? capturedArgs;
      final p = OpencodeProvider(
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

      p.setSessionId('s1', 'sess-123');
      p.sessionModels['s1'] = 'gpt-4';

      await p
          .sendMessage(
            message: 'continue',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
              model: 'claude-3',
            ),
            isFirstMessage: false,
          )
          .toList();

      expect(capturedArgs, isNot(contains('--session')));
      expect(p.getSessionId('s1'), isNull);
    });

    test('propagates stderr on error exit', () async {
      final p = OpencodeProvider(
        processStarter: _starterFor(
          stderr: ['opencode: command not found'],
          exitCode: 127,
        ),
      );

      final events = <ChatEvent>[];
      Object? capturedError;
      final completer = Completer<void>();
      p.sendMessage(
        message: 'x',
        config: const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
        ),
        isFirstMessage: true,
      ).listen(
        events.add,
        onError: (Object e) {
          capturedError = e;
          completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      await completer.future;

      expect(events.first.type, ChatEventType.userMessage);
      expect(capturedError, isNotNull);
      expect(capturedError.toString(), 'opencode: command not found');
    });

    test('looksLikeError detects error patterns', () {
      expect(OpencodeProvider.looksLikeError('rate limit exceeded'), isTrue);
      expect(OpencodeProvider.looksLikeError('Retrying in 30s'), isTrue);
      expect(OpencodeProvider.looksLikeError('normal output'), isFalse);
      expect(OpencodeProvider.looksLikeError('ok'), isFalse);
    });
  });

  group('OpenCodeLogWatcher.parseChunk', () {
    late List<(String, bool)> emitted;
    late OpenCodeLogWatcher watcher;

    setUp(() {
      emitted = <(String, bool)>[];
      watcher = OpenCodeLogWatcher(
        onRetry: (msg, {isFatal = false}) => emitted.add((msg, isFatal)),
      );
    });

    tearDown(() => watcher.stop());

    test('emits fatal rate-limit message for 429 with message', () {
      watcher.parseChunk(
        'opencode log line {"statusCode":429,"message":"Quota exceeded"} tail',
      );

      expect(emitted, hasLength(1));
      expect(emitted.single.$1, '⏳ Rate limit (429): Quota exceeded');
      expect(emitted.single.$2, isTrue);
    });

    test('uses fallback text for 429 without a message', () {
      watcher.parseChunk('{"statusCode":429} retrying in 30s');

      expect(emitted, hasLength(1));
      expect(
        emitted.single.$1,
        '⏳ Rate limit (429): Please try again later',
      );
      expect(emitted.single.$2, isTrue);
    });

    test('emits non-fatal warning for ERROR line with a message', () {
      watcher.parseChunk(
        '2024-01-01 ERROR {"statusCode":500,"message":"boom"}',
      );

      expect(emitted, hasLength(1));
      expect(emitted.single.$1, '⚠️ OpenCode: boom');
      expect(emitted.single.$2, isFalse);
    });

    test('emits warning for ERROR line with message but no status', () {
      watcher.parseChunk('ERROR {"message":"provider unavailable"}');

      expect(emitted, hasLength(1));
      expect(emitted.single.$1, '⚠️ OpenCode: provider unavailable');
      expect(emitted.single.$2, isFalse);
    });

    test('ignores non-429 status without ERROR marker', () {
      watcher.parseChunk('{"statusCode":200,"message":"all good"}');

      expect(emitted, isEmpty);
    });

    test('ignores message without status code and without ERROR', () {
      watcher.parseChunk('{"message":"just info"}');

      expect(emitted, isEmpty);
    });

    test('ignores chunks with neither status nor message', () {
      watcher.parseChunk('some plain log line without markers');

      expect(emitted, isEmpty);
    });

    test('does not re-emit duplicate messages', () {
      const chunk = '{"statusCode":429,"message":"slow down"}';

      watcher.parseChunk(chunk);
      watcher.parseChunk(chunk);

      expect(emitted, hasLength(1));
    });
  });
}
