import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';

/// Tests for the in-process `ui:` invocation path of [YoloitCliToolExecutor]
/// (`_tryInvokeInProcess`), pointed at a fake CLI HTTP server via the
/// `debugCliPortOverride` test hook.
void main() {
  // The automated test binding installs a mock HttpOverrides that fails every
  // request with 400; allow real loopback HTTP to the fake CLI server.
  HttpOverrides.global = null;

  group('YoloitCliToolExecutor in-process ui invocation', () {
    late HttpServer server;
    late StreamSubscription<BoardEvent> busSubscription;
    late List<BoardEvent> busEvents;

    Future<void> handleRequest(HttpRequest request) async {
      final Object payload;
      if (request.method == 'POST' && request.uri.path.endsWith('/panels')) {
        payload = <String, Object?>{
          'ok': true,
          'panel': <String, Object?>{
            'id': 'ui-9',
            'type': 'board.ui',
            'title': 'UI Panel',
          },
        };
      } else if (request.method == 'GET' &&
          request.uri.path.endsWith('/panels')) {
        payload = <String, Object?>{'panels': <dynamic>[]};
      } else {
        payload = <String, Object?>{'ok': true};
      }
      request.response
        ..headers.contentType = ContentType.json
        ..write(jsonEncode(payload));
      await request.response.close();
    }

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen(handleRequest);
      YoloitCliToolExecutor.debugCliPortOverride = server.port;
      busEvents = <BoardEvent>[];
      busSubscription = BoardEventBus.instance.stream.listen(busEvents.add);
    });

    tearDown(() async {
      YoloitCliToolExecutor.debugCliPortOverride = null;
      await busSubscription.cancel();
      await server.close(force: true);
    });

    test('executes ui:create in-process and emits a mutation event', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/echo');
      final result = await executor.invoke(
        'uicrt',
        <String, Object?>{'board': 'b1', 'title': 'UI Panel'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['executed'], isTrue);
      expect(
        (decoded['panel'] as Map<String, dynamic>)['id'],
        'ui-9',
      );

      await pumpEventQueue();
      final mutations = busEvents.whereType<BoardToolMutationEvent>().toList();
      expect(mutations, hasLength(1));
      expect(mutations.single.command, 'ui:create');
    });

    test('returns the in-process error without emitting an event', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/echo');
      final result = await executor.invoke(
        'uiget',
        <String, Object?>{'board': 'b1'},
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('No board.ui panel found'));

      await pumpEventQueue();
      expect(busEvents.whereType<BoardToolMutationEvent>(), isEmpty);
    });

    test('falls back to the subprocess for unsupported ui commands', () async {
      final executor = YoloitCliToolExecutor(executablePath: '/bin/echo');
      final result = await executor.invoke(
        'uist',
        <String, Object?>{
          'board': 'b1',
          'panel': 'p1',
          'state': <String, Object?>{'taps': 3},
        },
        argumentsPreNormalized: true,
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['exitCode'], 0);
      expect(decoded['command'] as String, contains('ui:set-state'));
      expect(decoded['stdout'] as String, contains('ui:set-state'));
    });
  });
}
