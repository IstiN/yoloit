import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/terminal/data/runtime_terminal_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The widgets binding replaces HttpClient with a mock that fails every
  // request; restore real networking so tests can talk to the fake runtime.
  io.HttpOverrides.global = null;

  tearDown(() {
    RuntimeTerminalClient.debugModeOverride = null;
    RuntimeTerminalClient.updateRequired.value = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  group('createSession', () {
    test('parses pid and existing flag from runtime response', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime
        ..sessionPid = 4321
        ..sessionExisting = false;

      final result = await fixture.client.createSession(
        sessionId: 's1',
        cwd: '/tmp/work',
        command: 'bash',
        env: const {'TERM': 'xterm-256color'},
        cols: 100,
        rows: 40,
      );

      expect(result.existing, isFalse);
      expect(result.shellPid, 4321);
      final body = fixture.runtime.lastCreateBody;
      expect(body, isNotNull);
      expect(body?['id'], 's1');
      expect(body?['cwd'], '/tmp/work');
      expect(body?['command'], 'bash');
      expect(body?['env'], {'TERM': 'xterm-256color'});
      expect(body?['cols'], 100);
      expect(body?['rows'], 40);
    });

    test('parses string pid and re-attached session', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime
        ..sessionPid = '777'
        ..sessionExisting = true;

      final result = await fixture.client.createSession(
        sessionId: 's1',
        cwd: '/tmp/work',
      );

      expect(result.existing, isTrue);
      expect(result.shellPid, 777);
    });

    test('returns zero pid when session payload is missing', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.omitSession = true;

      final result = await fixture.client.createSession(
        sessionId: 's1',
        cwd: '/tmp/work',
      );

      expect(result.shellPid, 0);
    });

    test('throws StateError when runtime returns an error status', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.createStatus = HttpStatus.internalServerError;

      await expectLater(
        fixture.client.createSession(sessionId: 's1', cwd: '/tmp/work'),
        throwsStateError,
      );
    });
  });

  group('streamSession', () {
    test('yields output events until the exit event', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamScripts = [
        [
          '{"type":"output","data":"hello"}\n\n{"type":"output","data":"world"}\n{"type":"exit"}\n',
        ],
      ];

      final events = await fixture.client.streamSession('s1').toList();

      expect(events, ['hello', 'world']);
      expect(fixture.runtime.streamRequests, 1);
    });

    test('completes when the runtime reports 404', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamStatuses = [HttpStatus.notFound];

      final events = await fixture.client.streamSession('gone').toList();

      expect(events, isEmpty);
    });

    test('throws StateError on unexpected stream status', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamStatuses = [HttpStatus.internalServerError];

      await expectLater(
        fixture.client.streamSession('s1').toList(),
        throwsStateError,
      );
    });

    test('reattaches when the stream drops but the runtime stays healthy',
        () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamScripts = [
        ['{"type":"output","data":"a"}\n'],
        ['{"type":"output","data":"b"}\n{"type":"exit"}\n'],
      ];

      final events = await fixture.client.streamSession('s1').toList();

      expect(events, ['a', 'b']);
      expect(fixture.runtime.streamRequests, 2);
    });

    test('completes when the stream drops and the runtime is gone', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamScripts = [
        ['{"type":"output","data":"a"}\n'],
      ];
      fixture.runtime.onStreamRequest = (_) {
        fixture.runtime.healthy = false;
      };

      final events = await fixture.client.streamSession('s1').toList();

      expect(events, ['a']);
      expect(fixture.runtime.streamRequests, 1);
    });

    test('reconnects with ?since= last delivered seq to avoid replay '
        'duplicates', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.streamScripts = [
        ['{"type":"output","data":"a","seq":5}\n'],
        ['{"type":"output","data":"b","seq":6}\n{"type":"exit","seq":7}\n'],
      ];

      final events = await fixture.client.streamSession('s1').toList();

      expect(events, ['a', 'b']);
      expect(fixture.runtime.streamRequests, 2);
      expect(fixture.runtime.streamQueries[0], isEmpty);
      expect(fixture.runtime.streamQueries[1], 'since=5');
    });

    test('never yields the same seq twice on reconnect', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      // The reconnected stream re-sends seq 5 (replay/live overlap) before
      // continuing with new output — the client must drop the duplicate.
      const replayed =
          '{"type":"output","data":"a","seq":5}\n'
          '{"type":"output","data":"b","seq":6}\n'
          '{"type":"exit","seq":7}\n';
      fixture.runtime.streamScripts = [
        ['{"type":"output","data":"a","seq":5}\n'],
        [replayed],
      ];

      final events = await fixture.client.streamSession('s1').toList();

      expect(events, ['a', 'b']);
    });
  });

  group('runtime log rotation', () {
    test('rotates an oversized log to runtime.log.old', () async {
      final dir = await Directory.systemTemp.createTemp('log_rotate_test');
      addTearDown(() => dir.delete(recursive: true));
      final log = File('${dir.path}/runtime.log');
      await log.writeAsBytes(List.filled(2048, 120));
      await File('${dir.path}/runtime.log.old').writeAsString('stale');

      await RuntimeTerminalClient.rotateLogIfNeeded(log.path, maxBytes: 1024);

      expect(await log.exists(), isFalse);
      expect(await File('${dir.path}/runtime.log.old').length(), 2048);
    });

    test('leaves a small log untouched', () async {
      final dir = await Directory.systemTemp.createTemp('log_rotate_test');
      addTearDown(() => dir.delete(recursive: true));
      final log = File('${dir.path}/runtime.log');
      await log.writeAsString('small');

      await RuntimeTerminalClient.rotateLogIfNeeded(log.path, maxBytes: 1024);

      expect(await log.readAsString(), 'small');
      expect(await File('${dir.path}/runtime.log.old').exists(), isFalse);
    });

    test('ignores a missing log file', () async {
      final dir = await Directory.systemTemp.createTemp('log_rotate_test');
      addTearDown(() => dir.delete(recursive: true));

      await RuntimeTerminalClient.rotateLogIfNeeded(
        '${dir.path}/runtime.log',
        maxBytes: 1024,
      );

      expect(await File('${dir.path}/runtime.log.old').exists(), isFalse);
    });
  });

  group('input, resize and kill', () {
    test('input posts base64-encoded data', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);

      await fixture.client.input('s1', 'echo hi\n');

      expect(fixture.runtime.lastInputData, 'echo hi\n');
    });

    test('resize posts cols and rows', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);

      await fixture.client.resize('s1', 132, 43);

      expect(fixture.runtime.lastResizeBody?['cols'], 132);
      expect(fixture.runtime.lastResizeBody?['rows'], 43);
    });

    test('resize ignores an expired session (404)', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.resizeStatus = HttpStatus.notFound;

      await fixture.client.resize('s1', 80, 24);
    });

    test('resize rethrows unexpected errors', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      fixture.runtime.resizeStatus = HttpStatus.internalServerError;

      await expectLater(
        fixture.client.resize('s1', 80, 24),
        throwsStateError,
      );
    });

    test('kill posts a kill request for the session', () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);

      await fixture.client.kill('s1');

      expect(fixture.runtime.killCalls, 1);
    });
  });

  group('ensureStarted', () {
    test('does not spawn a runtime when the existing one is healthy',
        () async {
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final client = _FakeStartClient(
        runtimeHome: fixture.home.path,
        port: fixture.runtime.port,
      );

      await client.ensureStarted();

      expect(client.startCalls, 0);
      expect(fixture.runtime.healthChecks, greaterThan(0));
    });

    test('starts the runtime when no port file exists', () async {
      final fixture = await _createFixture(
        seedDebugMtime: false,
        seedPort: false,
      );
      addTearDown(fixture.dispose);
      final client = _FakeStartClient(
        runtimeHome: fixture.home.path,
        port: fixture.runtime.port,
      );

      await client.ensureStarted();

      expect(client.startCalls, 1);
      expect(fixture.runtime.healthChecks, greaterThan(0));
    });
  });

  group('binary update check', () {
    test('flags an update when the bundled binary size differs', () async {
      RuntimeTerminalClient.debugModeOverride = false;
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      _mockBundledBinary([1, 2, 3, 4, 5]);
      await File('${fixture.home.path}/yoloitd').writeAsBytes([1, 2, 3]);

      await fixture.client.ensureStarted();

      expect(RuntimeTerminalClient.updateRequired.value, isTrue);
    });

    test('leaves the flag clear when binary sizes match', () async {
      RuntimeTerminalClient.debugModeOverride = false;
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      _mockBundledBinary([1, 2, 3, 4]);
      await File('${fixture.home.path}/yoloitd').writeAsBytes([9, 9, 9, 9]);

      await fixture.client.ensureStarted();

      expect(RuntimeTerminalClient.updateRequired.value, isFalse);
    });

    test('ignores a missing installed binary', () async {
      RuntimeTerminalClient.debugModeOverride = false;
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      _mockBundledBinary([1, 2, 3, 4]);

      await fixture.client.ensureStarted();

      expect(RuntimeTerminalClient.updateRequired.value, isFalse);
    });
  });

  group('restartRuntime', () {
    test('kills the stale pid, re-extracts the binary and starts fresh',
        () async {
      RuntimeTerminalClient.debugModeOverride = false;
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final client = _FakeStartClient(
        runtimeHome: fixture.home.path,
        port: fixture.runtime.port,
      );
      _mockBundledBinary([7, 7, 7]);
      RuntimeTerminalClient.updateRequired.value = true;

      // A guaranteed-dead pid: _killPidFile must attempt SIGTERM, probe with
      // `kill -0` and skip SIGKILL because the process is already gone.
      final stale = await Process.start('sleep', const ['30']);
      final deadPid = stale.pid;
      stale.kill(ProcessSignal.sigkill);
      await stale.exitCode;
      await File('${fixture.home.path}/runtime.pid').writeAsString('$deadPid');

      await client.restartRuntime();

      expect(client.startCalls, 1);
      expect(RuntimeTerminalClient.updateRequired.value, isFalse);
      final binary = File('${fixture.home.path}/yoloitd');
      expect(await binary.readAsBytes(), [7, 7, 7]);
    });

    test('keeps the installed binary when its size matches the bundle',
        () async {
      RuntimeTerminalClient.debugModeOverride = false;
      final fixture = await _createFixture();
      addTearDown(fixture.dispose);
      final client = _FakeStartClient(
        runtimeHome: fixture.home.path,
        port: fixture.runtime.port,
      );
      _mockBundledBinary([5, 5, 5]);
      final binary = File('${fixture.home.path}/yoloitd');
      await binary.writeAsBytes([4, 4, 4]);

      await client.restartRuntime();

      // Same size as the bundle: no re-extraction, content untouched.
      expect(await binary.readAsBytes(), [4, 4, 4]);
      expect(RuntimeTerminalClient.updateRequired.value, isFalse);
    });
  });
}

class _FakeStartClient extends RuntimeTerminalClient {
  _FakeStartClient({required super.runtimeHome, required this.port});

  final int port;
  int startCalls = 0;

  @override
  Future<void> startRuntime() async {
    startCalls++;
    await File('$runtimeHome/runtime.port').writeAsString('$port');
  }
}

class _Fixture {
  _Fixture(this.home, this.runtime, this.client);

  final Directory home;
  final _FakeRuntime runtime;
  final RuntimeTerminalClient client;

  Future<void> dispose() async {
    await runtime.server.close(force: true);
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  }
}

Future<_Fixture> _createFixture({
  bool seedDebugMtime = true,
  bool seedPort = true,
}) async {
  final home = await Directory.systemTemp.createTemp('runtime_client_test');
  final runtime = _FakeRuntime(await _bindServer());
  runtime.server.listen(runtime.handle);
  if (seedDebugMtime) {
    // In debug mode ensureStarted() compares the live tools/yoloitd binary
    // mtime with the stored one; seed it so the stale-kill is a no-op and
    // the port file survives.
    final script = File('tools/yoloitd/yoloitd');
    if (await script.exists()) {
      final mtime = (await script.lastModified()).millisecondsSinceEpoch;
      await File('${home.path}/script.mtime').writeAsString('$mtime');
    }
  }
  if (seedPort) {
    await File('${home.path}/runtime.port').writeAsString('${runtime.port}');
  }
  return _Fixture(home, runtime, RuntimeTerminalClient(runtimeHome: home.path));
}

Future<HttpServer> _bindServer() async {
  Object? lastError;
  for (var attempt = 0; attempt < 10; attempt++) {
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } on SocketException catch (e) {
      lastError = e;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }
  throw StateError('could not bind test server: $lastError');
}

void _mockBundledBinary(List<int> bytes) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler('flutter/assets', (message) async {
    return ByteData.sublistView(Uint8List.fromList(bytes));
  });
}

class _FakeRuntime {
  _FakeRuntime(this.server);

  final HttpServer server;

  bool healthy = true;
  int healthChecks = 0;

  int createStatus = HttpStatus.ok;
  Object? sessionPid = 4321;
  bool sessionExisting = false;
  bool omitSession = false;
  Map<String, dynamic>? lastCreateBody;

  String? lastInputData;
  Map<String, dynamic>? lastResizeBody;
  int resizeStatus = HttpStatus.ok;
  int killCalls = 0;

  int streamRequests = 0;
  List<int> streamStatuses = const [];
  List<List<String>> streamScripts = const [];
  final List<String> streamQueries = [];
  void Function(int requestNumber)? onStreamRequest;

  int get port => server.port;

  void handle(HttpRequest request) {
    unawaited(_handle(request));
  }

  Future<void> _handle(HttpRequest request) async {
    final path = request.uri.path;
    if (path == '/health') {
      healthChecks++;
      _respond(
        request,
        healthy ? HttpStatus.ok : HttpStatus.serviceUnavailable,
      );
      return;
    }
    if (path == '/sessions' && request.method == 'POST') {
      final body = await utf8.decoder.bind(request).join();
      lastCreateBody = jsonDecode(body) as Map<String, dynamic>;
      if (createStatus != HttpStatus.ok) {
        _respond(request, createStatus);
        return;
      }
      _respondJson(request, {
        'existing': sessionExisting,
        if (!omitSession) 'session': {'pid': sessionPid},
      });
      return;
    }
    final segments = path.split('/');
    if (segments.length == 4 && segments[1] == 'sessions') {
      switch (segments[3]) {
        case 'stream':
          await _handleStream(request);
          return;
        case 'input':
          final body = await utf8.decoder.bind(request).join();
          final decoded = jsonDecode(body) as Map<String, dynamic>;
          lastInputData = utf8.decode(base64Decode(decoded['data'] as String));
          _respondJson(request, const {});
          return;
        case 'resize':
          final body = await utf8.decoder.bind(request).join();
          lastResizeBody = jsonDecode(body) as Map<String, dynamic>;
          if (resizeStatus == HttpStatus.ok) {
            _respondJson(request, const {});
          } else {
            _respond(request, resizeStatus);
          }
          return;
        case 'kill':
          killCalls++;
          await utf8.decoder.bind(request).join();
          _respondJson(request, const {});
          return;
      }
    }
    _respond(request, HttpStatus.notFound);
  }

  Future<void> _handleStream(HttpRequest request) async {
    streamRequests++;
    streamQueries.add(request.uri.query);
    final index = streamRequests - 1;
    onStreamRequest?.call(streamRequests);
    final status = index < streamStatuses.length
        ? streamStatuses[index]
        : HttpStatus.ok;
    request.response.statusCode = status;
    if (status == HttpStatus.ok && index < streamScripts.length) {
      for (final chunk in streamScripts[index]) {
        request.response.write(chunk);
        await request.response.flush();
      }
    }
    await request.response.close();
  }

  void _respond(HttpRequest request, int status) {
    request.response.statusCode = status;
    request.response.close();
  }

  void _respondJson(HttpRequest request, Map<String, Object?> payload) {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(payload));
    request.response.close();
  }
}
