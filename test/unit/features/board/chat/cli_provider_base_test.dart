import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cli_provider_base.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// A minimal concrete provider for testing [CliProviderBase].
class _TestProvider extends CliProviderBase {
  _TestProvider({super.processStarter}) : super(agentId: 'test');

  @override
  String get debugPrefix => '[Test]';

  @override
  String get displayName => 'Test';

  @override
  String get defaultLaunchCommand => 'test-cmd';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  Future<List<String>> buildArgs({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    required List<String> attachments,
    required ChatRuntimeContext? runtimeContext,
    required List<String> baseArgs,
    List<String> extraCmdArgs = const [],
  }) async {
    return [...extraCmdArgs, ...baseArgs, '-p', message];
  }

  @override
  List<ChatEvent> parseLine(String line, String sessionName) {
    final json = jsonDecode(line) as Map<String, dynamic>;
    final role = json['role'] as String?;
    if (role == 'assistant') {
      return [
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'test.assistant',
          data: {'content': json['content']},
        ),
      ];
    }
    if (role == 'meta' && json['type'] == 'session') {
      storeSessionId(sessionName, json['id'] as String);
    }
    return const [];
  }
}

/// Fake process that feeds pre-recorded stdout/stderr and returns a given
/// exit code.
class _FakeProcess implements Process {
  _FakeProcess({
    required List<String> stdoutLines,
    List<String> stderrLines = const [],
    required int exitCode,
    this.delay = Duration.zero,
  })  : _stdoutController = StreamController<List<int>>(),
        _stderrController = StreamController<List<int>>(),
        _exitCode = exitCode {
    _emitLines(stdoutLines, _stdoutController);
    _emitLines(stderrLines, _stderrController);
  }

  final StreamController<List<int>> _stdoutController;
  final StreamController<List<int>> _stderrController;
  final int _exitCode;
  final Duration delay;
  bool _stdinClosed = false;

  static void _emitLines(
    List<String> lines,
    StreamController<List<int>> controller,
  ) {
    Future.microtask(() async {
      for (final line in lines) {
        controller.add(utf8.encode('$line\n'));
        await Future.delayed(Duration(milliseconds: 10));
      }
      await controller.close();
    });
  }

  @override
  Stream<List<int>> get stdout => _stdoutController.stream;

  @override
  Stream<List<int>> get stderr => _stderrController.stream;

  @override
  IOSink get stdin => _FakeIOSink(onClose: () => _stdinClosed = true);

  @override
  Future<int> get exitCode async {
    if (delay != Duration.zero) await Future.delayed(delay);
    return _exitCode;
  }

  @override
  int get pid => 12345;

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

typedef _FakeStarter = Future<Process> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
});

void main() {
  group('CliProviderBase', () {
    late List<Map<String, dynamic>> capturedStarts;
    late _FakeStarter starter;

    setUp(() {
      capturedStarts = [];
      starter = (exe, args, {workingDirectory, environment}) async {
        capturedStarts.add({
          'exe': exe,
          'args': args,
          'wd': workingDirectory,
          'env': environment,
        });
        return _FakeProcess(
          stdoutLines: const [
            '{"role":"assistant","content":"hello"}',
            '{"role":"meta","type":"session","id":"sess-42"}',
          ],
          stderrLines: const ['warn'],
          exitCode: 0,
        );
      };
    });

    test('starts process with enriched args', () async {
      final provider = _TestProvider(processStarter: starter);
      final stream = provider.sendMessage(
        message: 'hi',
        config: const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          model: 'gpt-4',
        ),
        isFirstMessage: true,
      );

      final events = await stream.toList();
      expect(events, hasLength(1));
      expect(events.first.type, ChatEventType.assistantMessage);

      expect(capturedStarts, hasLength(1));
      final start = capturedStarts.first;
      expect(start['exe'], 'test-cmd');
      expect(start['args'], containsAll(['--model', 'gpt-4', '-p', 'hi']));
      expect(start['wd'], '/tmp');
      expect((start['env'] as Map)['PATH'], isNotEmpty);
    });

    test('reuses session id on resume', () async {
      final provider = _TestProvider(processStarter: starter);
      provider.setSessionId('s1', 'sess-42');

      await provider
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
              model: 'gpt-4',
            ),
            isFirstMessage: false,
          )
          .toList();

      final args = capturedStarts.first['args'] as List;
      expect(args, containsAll(['--session', 'sess-42']));
    });

    test('parses session id from stdout meta event', () async {
      final provider = _TestProvider(processStarter: starter);

      await provider
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
          )
          .toList();

      expect(provider.getSessionId('s1'), 'sess-42');
    });

    test('emits error on non-zero exit', () async {
      final provider = _TestProvider(
        processStarter: (exe, args, {workingDirectory, environment}) async =>
            _FakeProcess(
          stdoutLines: const [],
          stderrLines: const ['something broke'],
          exitCode: 1,
        ),
      );

      final stream = provider.sendMessage(
        message: 'hi',
        config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
        isFirstMessage: true,
      );

      expectLater(
        stream,
        emitsError(
          isA<Object>().having((e) => e.toString(), 'msg', 'something broke'),
        ),
      );
    });

    test('stop kills process', () async {
      final provider = _TestProvider(processStarter: starter);

      final stream = provider.sendMessage(
        message: 'hi',
        config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
        isFirstMessage: true,
      );

      // Wait for the process to actually start.
      await stream.first;
      expect(provider.isRunning('s1'), isTrue);
      await provider.stop('s1');
      expect(provider.isRunning('s1'), isFalse);
    });

    test('dispose kills all processes', () async {
      final provider = _TestProvider(processStarter: starter);

      final stream1 = provider.sendMessage(
        message: 'a',
        config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
        isFirstMessage: true,
      );
      final stream2 = provider.sendMessage(
        message: 'b',
        config: const ChatSessionConfig(sessionName: 's2', workingDir: '/tmp'),
        isFirstMessage: true,
      );

      // Wait for both processes to start.
      await stream1.first;
      await stream2.first;

      expect(provider.isRunning('s1'), isTrue);
      expect(provider.isRunning('s2'), isTrue);

      provider.dispose();

      expect(provider.isRunning('s1'), isFalse);
      expect(provider.isRunning('s2'), isFalse);
    });

    test('detach clears references without killing', () async {
      final provider = _TestProvider(processStarter: starter);

      provider.sendMessage(
        message: 'a',
        config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
        isFirstMessage: true,
      );

      provider.detach();
      expect(provider.isRunning('s1'), isFalse);
      // Process still alive in OS; we just dropped the reference.
    });

    test('closes stdin after start', () async {
      late _FakeProcess proc;
      final provider = _TestProvider(
        processStarter: (exe, args, {workingDirectory, environment}) async {
          proc = _FakeProcess(
            stdoutLines: const ['{"role":"assistant","content":"x"}'],
            exitCode: 0,
          );
          return proc;
        },
      );

      await provider
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
            isFirstMessage: true,
          )
          .toList();

      expect(proc.stdinClosed, isTrue);
    });

    test('handles malformed json gracefully', () async {
      final provider = _TestProvider(
        processStarter: (exe, args, {workingDirectory, environment}) async =>
            _FakeProcess(
          stdoutLines: const [
            'not-json',
            '{"role":"assistant","content":"ok"}',
          ],
          exitCode: 0,
        ),
      );

      final events = await provider
          .sendMessage(
            message: 'hi',
            config: const ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
            isFirstMessage: true,
          )
          .toList();

      expect(events, hasLength(1));
      expect(events.first.data['content'], 'ok');
    });
  });
}
