import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/features/terminal/data/pty_wrapper.dart';
import 'package:yoloit/features/terminal/data/runtime_terminal_client.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';

void main() {
  tearDown(() {
    PlatformShell.setInstance(const MacosPlatformShell());
  });

  test('runtime terminal backend sends enriched PATH to daemon', () async {
    PlatformShell.setInstance(
      const MacosPlatformShell(homeOverride: '/Users/test'),
    );
    final client = _FakeRuntimeTerminalClient();
    final backend = RuntimeTerminalBackend(client: client);

    await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
      extraEnv: {'CUSTOM': 'value'},
    );

    expect(client.lastCommand, isNotNull);
    expect(client.lastEnv?['CUSTOM'], 'value');
    expect(client.lastEnv?['TERM'], 'xterm-256color');
    expect(client.lastEnv?['COLORTERM'], 'truecolor');
    final path = client.lastEnv?['PATH'] ?? '';
    expect(path.split(':'), contains('/Users/test/.local/bin'));
    expect(path.split(':'), contains('/opt/homebrew/bin'));
  });
  test('runtime terminal backend reattaches without killing existing session',
      () async {
    final client = _FakeRuntimeTerminalClient(existingOnCreate: true);
    final backend = RuntimeTerminalBackend(client: client);

    final process = await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
    );

    expect(client.killCalls, isEmpty);
    expect(process.attachedExisting, isTrue);
  });

  test('runtime terminal backend forceNewShell kills existing session', () async {
    final client = _FakeRuntimeTerminalClient(existingOnCreate: true);
    final backend = RuntimeTerminalBackend(client: client);

    final process = await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
      forceNewShell: true,
    );

    expect(client.killCalls, ['session-1']);
    expect(client.createCalls, 2);
    expect(process.attachedExisting, isFalse);
  });

  test('runtime terminal backend registers shell session for resource monitor',
      () async {
    final client = _FakeRuntimeTerminalClient();
    final backend = RuntimeTerminalBackend(client: client);
    const metadata = ResourceSessionMetadata(
      kind: 'terminal',
      boardId: 'board-1',
      boardName: 'Work',
      panelId: 'panel-1',
      panelTitle: 'Shell',
      panelType: 'board.terminal',
      provider: 'terminal',
    );

    await backend.launch(
      sessionId: 'board_terminal_1',
      workspacePath: '/tmp/workspace',
      label: 'Shell',
      metadata: metadata,
    );

    expect(
      ResourceMonitorService.instance.registeredPids,
      contains(42),
    );
    expect(
      ResourceMonitorService.instance.metadataForRuntimeSession(
        'board_terminal_1',
      )?.panelId,
      'panel-1',
    );

    ResourceMonitorService.instance.unregisterSession(42);
    ResourceMonitorService.instance.unregisterRuntimeSession('board_terminal_1');
  });

  group('buffered utf8 decoder', () {
    Future<List<String>> decode(List<List<int>> chunks) {
      return Stream.fromIterable(chunks)
          .transform(TerminalProcess.utf8DecoderForTesting())
          .toList();
    }

    test('passes ascii through unchanged', () async {
      expect(await decode([utf8.encode('hello')]), ['hello']);
    });

    test('buffers a 2-byte sequence split across chunks', () async {
      // 'é' = 0xC3 0xA9
      final chunks = [
        [0x68, 0xC3], // 'h' + first byte of 'é'
        [0xA9, 0x6C, 0x6C, 0x6F], // second byte + 'llo'
      ];
      expect(await decode(chunks), ['h', 'éllo']);
    });

    test('buffers a 3-byte sequence split across chunks', () async {
      // '€' = 0xE2 0x82 0xAC
      final chunks = [
        [0xE2],
        [0x82, 0xAC],
      ];
      expect(await decode(chunks), ['€']);
    });

    test('buffers a 4-byte sequence split across many chunks', () async {
      // '🙂' = 0xF0 0x9F 0x99 0x82
      final chunks = [
        [0x61, 0xF0], // 'a' + first byte
        [0x9F],
        [0x99, 0x82],
      ];
      expect(await decode(chunks), ['a', '🙂']);
    });

    test('decodes immediately when a chunk ends on a boundary', () async {
      final chunks = [utf8.encode('héllo'), utf8.encode('!')];
      expect(await decode(chunks), ['héllo', '!']);
    });

    test('drops a lone continuation byte left in the carry', () async {
      expect(await decode([[0x80]]), isEmpty);
    });

    test('replaces malformed lead bytes instead of crashing', () async {
      final output = await decode([[0xFF, 0x61]]);
      expect(output, ['\uFFFDa']);
    });
  });

  group('ack-on-data backpressure wrapper', () {
    test('acks exactly once per delivered chunk', () async {
      var acks = 0;
      final chunks = [
        [1, 2],
        [3],
        [4, 5, 6],
      ];
      final received = await TerminalProcess.ackOnDataForTesting(
        () => acks++,
        Stream.fromIterable(chunks),
      ).toList();
      expect(received, chunks);
      expect(acks, chunks.length);
    });

    test('acks once more on cancel so the native read thread can exit',
        () async {
      var acks = 0;
      final source = StreamController<List<int>>();
      final stream = TerminalProcess.ackOnDataForTesting(
        () => acks++,
        source.stream,
      );
      final sub = stream.listen((_) {});
      source.add([1]);
      await Future<void>.delayed(Duration.zero);
      expect(acks, 1);
      await sub.cancel();
      expect(acks, 2);
      await source.close();
    });

    test('acks exactly once per delivered byte chunk (Uint8List)', () async {
      var acks = 0;
      final chunks = [
        Uint8List.fromList([1, 2]),
        Uint8List.fromList([3]),
        Uint8List.fromList([4, 5, 6]),
      ];
      final received = await TerminalProcess.ackOnDataForTesting(
        () => acks++,
        Stream<Uint8List>.fromIterable(chunks),
      ).toList();
      expect(received, chunks);
      expect(acks, chunks.length);
    });
  });

  group('terminal process byte channel', () {
    test('fromPty propagates the byte stream when the PTY provides one', () {
      final pty = _FakePty(withBytes: true);
      final process = TerminalProcess.fromPty(pty);

      expect(process.output, same(pty.outputStream));
      expect(process.outputBytes, same(pty.byteStream));
    });

    test('fromPty leaves outputBytes null for String-only PTYs', () {
      final pty = _FakePty(withBytes: false);
      final process = TerminalProcess.fromPty(pty);

      expect(process.outputBytes, isNull);
    });
  });
}

/// A [Pty] with manually driven streams; [withBytes] toggles the optional
/// byte channel the flutter_pty backend exposes.
class _FakePty implements Pty {
  _FakePty({required this.withBytes});

  final bool withBytes;

  // Only declared on the web-stub Pty variant, which the analyzer resolves
  // the conditional export to; harmless extra members against the io one.
  @override
  String get executable => 'fake';

  @override
  List<String> get arguments => const [];

  // ignore: close_sinks — streams are never pumped in these tests.
  final stringController = StreamController<String>();
  // ignore: close_sinks — streams are never pumped in these tests.
  final byteController = StreamController<Uint8List>();

  // StreamController.stream hands out a NEW wrapper per access, so the
  // stream instances are captured once here — identity is what fromPty
  // propagation is asserted against.
  late final Stream<String> outputStream = stringController.stream;
  late final Stream<Uint8List> byteStream = byteController.stream;

  @override
  Stream<String> get output => outputStream;

  @override
  Stream<Uint8List>? get outputBytes => withBytes ? byteStream : null;

  @override
  Future<int> get exitCode => Completer<int>().future;

  @override
  int get pid => 0;

  @override
  void write(Uint8List data) {}

  @override
  void resize(int rows, int cols) {}

  // Parameter typed dynamic so the override is valid against BOTH the io
  // (ProcessSignal) and web-stub (dynamic) Pty variants — the analyzer
  // resolves the conditional export to the stub.
  @override
  bool kill([dynamic signal]) => true;

  @override
  void ackRead() {}
}

class _FakeRuntimeTerminalClient extends RuntimeTerminalClient {
  _FakeRuntimeTerminalClient({this.existingOnCreate = false})
    : super(runtimeHome: '/tmp/yoloit-test-runtime');

  final bool existingOnCreate;
  Map<String, String>? lastEnv;
  String? lastCommand;
  final killCalls = <String>[];
  var createCalls = 0;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<RuntimeSessionCreateResult> createSession({
    required String sessionId,
    required String cwd,
    String? command,
    Map<String, String> env = const {},
    int cols = 120,
    int rows = 30,
  }) async {
    createCalls++;
    lastEnv = env;
    lastCommand = command;
    return RuntimeSessionCreateResult(
      existing: existingOnCreate && createCalls == 1,
      shellPid: 42,
    );
  }

  @override
  Future<void> kill(String sessionId) async {
    killCalls.add(sessionId);
  }

  @override
  Stream<String> streamSession(String sessionId) => const Stream.empty();
}
