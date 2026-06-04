import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/codex_cli_provider.dart';
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
  group('CodexCliProvider', () {
    test('provider metadata', () {
      final p = CodexCliProvider();
      expect(p.providerId, 'codex');
      expect(p.displayName, 'Codex');
      expect(p.supportsImages, isTrue);
      expect(p.imageMode, ChatImageMode.filePath);
      expect(p.passSessionArgs, isFalse);
    });

    test('emits assistant message from JSON stdout', () async {
      final p = CodexCliProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"item.completed","item":{"type":"agent_message","text":"hello","id":"msg-1"}}',
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
      expect(events.first.data['messageId'], 'msg-1');
    });

    test('stores thread id from thread.started', () async {
      final p = CodexCliProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"thread.started","thread_id":"th-99"}',
          '{"type":"item.completed","item":{"type":"agent_message","text":"ok","id":"m1"}}',
        ]),
      );

      await p
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(p.getSessionId('s1'), 'th-99');
    });

    test('emits result on turn.completed', () async {
      final p = CodexCliProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"turn.completed","usage":{"output_tokens":42}}',
        ]),
      );

      final events = await p
          .sendMessage(
            message: 'x',
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
    });

    test('propagates error on turn.failed', () async {
      final p = CodexCliProvider(
        processStarter: _starterFor(stdout: [
          '{"type":"turn.failed","message":"rate limited"}',
        ]),
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
            contains('rate limited'),
          ),
        ),
      );
    });

    test('propagates stderr on error exit', () async {
      final p = CodexCliProvider(
        processStarter: _starterFor(
          stderr: ['codex: command not found'],
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
            'codex: command not found',
          ),
        ),
      );
    });

    test('resumes with stored thread id', () async {
      late List<String> capturedArgs;
      final p = CodexCliProvider(
        processStarter: (String exe, List<String> args,
                {String? workingDirectory,
                Map<String, String>? environment}) {
          capturedArgs = args;
          return Future.value(_FakeProcess(
            stdoutLines: const ['{"type":"turn.completed"}'],
            exitCode: 0,
          ));
        },
      );

      p.setSessionId('s1', 'th-123');

      await p
          .sendMessage(
            message: 'continue',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: false,
          )
          .toList();

      expect(capturedArgs, containsAll(['exec', 'resume', 'th-123']));
    });
  });
}
