import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/chat/kimi_cli_provider.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Fake process that replays recorded stdout/stderr lines.
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
  bool _stdinClosed = false;

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
  IOSink get stdin => _FakeIOSink(onClose: () => _stdinClosed = true);

  @override
  Future<int> get exitCode async => _exitCode;

  @override
  int get pid => 42;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;

  bool get stdinClosed => _stdinClosed;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeIOSink implements IOSink {
  _FakeIOSink({required this.onClose});
  final void Function() onClose;

  @override
  Future close() async => onClose();

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
  group('KimiCliProvider', () {
    test('provider metadata', () {
      final p = KimiCliProvider(wireJsonlPath: '');
      expect(p.providerId, 'kimi');
      expect(p.displayName, 'Kimi');
      expect(p.supportsImages, isTrue);
      expect(p.imageMode, ChatImageMode.filePath);
    });

    test('emits assistant message from JSON stdout', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(stdout: [
          '{"role":"assistant","content":"hello world"}',
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
      expect(events.first.data['content'], 'hello world');
    });

    test('handles list-style content', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(stdout: [
          '{"role":"assistant","content":[{"text":"part1"},{"text":"part2"}]}',
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

      expect(events.first.data['content'], 'part1part2');
    });

    test('includes thinking parts as quoted block', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(stdout: [
          '{"role":"assistant","content":[{"type":"think","think":"I need to check..."},{"type":"text","text":"Here is the answer."}]}',
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

      expect(events.first.data['content'], contains('> **Thinking**'));
      expect(events.first.data['content'], contains('I need to check...'));
      expect(events.first.data['content'], contains('Here is the answer.'));
    });

    test('stores session id from meta event', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(stdout: [
          '{"role":"meta","type":"session.resume_hint","session_id":"sess-99"}',
          '{"role":"assistant","content":"ok"}',
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

      expect(p.getSessionId('s1'), 'sess-99');
    });

    test('ignores unknown roles', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(stdout: [
          '{"role":"system","content":"setup"}',
          '{"role":"assistant","content":"hi"}',
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
      expect(events.first.data['content'], 'hi');
    });

    test('propagates stderr on error exit', () async {
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: _starterFor(
          stderr: ['kimi: command not found'],
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
            'kimi: command not found',
          ),
        ),
      );
    });

    test('builds args with model and plan mode', () async {
      late List<String> capturedArgs;
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: (String exe, List<String> args,
                {String? workingDirectory,
                Map<String, String>? environment}) {
          capturedArgs = args;
          return Future.value(_FakeProcess(
            stdoutLines: const ['{"role":"assistant","content":"x"}'],
            exitCode: 0,
          ));
        },
      );

      await p
          .sendMessage(
            message: 'hello',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
              model: 'kimi-k2',
              mode: 'plan',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(capturedArgs, containsAll(['--model', 'kimi-k2', '--plan']));
      final promptIndex = capturedArgs.indexOf('-p');
      expect(promptIndex, greaterThanOrEqualTo(0));
      expect(capturedArgs[promptIndex + 1], contains('hello'));
    });

    test('resumes with stored session id', () async {
      late List<String> capturedArgs;
      final p = KimiCliProvider(
        wireJsonlPath: '',
        processStarter: (String exe, List<String> args,
                {String? workingDirectory,
                Map<String, String>? environment}) {
          capturedArgs = args;
          return Future.value(_FakeProcess(
            stdoutLines: const ['{"role":"assistant","content":"x"}'],
            exitCode: 0,
          ));
        },
      );

      p.setSessionId('s1', 'sess-123');

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

      expect(capturedArgs, containsAll(['--session', 'sess-123']));
    });
  });
}
