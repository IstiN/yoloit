import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/board_relay_client.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test('relay answers hub request frames from the local board state',
      () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.createBoard(name: 'Relay board');

    // Minimal in-process hub: upgrades /api/relay/connect to a WebSocket and
    // records every frame the device sends back.
    final hub = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => hub.close(force: true));
    final frames = StreamController<Map<String, dynamic>>();
    addTearDown(frames.close);
    WebSocket? hubSocket;
    final hubSub = hub.listen((request) async {
      if (request.uri.path == '/api/relay/connect' &&
          WebSocketTransformer.isUpgradeRequest(request)) {
        hubSocket = await WebSocketTransformer.upgrade(request);
        hubSocket!.listen((data) {
          frames.add(jsonDecode(data as String) as Map<String, dynamic>);
        });
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    });
    addTearDown(hubSub.cancel);

    final relay = BoardRelayClient.instance;
    addTearDown(relay.stop);
    await relay.start(
      cubit,
      hubUrl: 'http://127.0.0.1:${hub.port}',
      deviceId: 'dev-1',
      deviceKey: 'key-1',
    );

    // Wait for the outbound connection (poll, generous budget).
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (relay.status.value != BoardRelayStatus.connected &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(relay.status.value, BoardRelayStatus.connected);
    expect(hubSocket, isNotNull);

    // Malformed frames and frames without an id must be ignored silently.
    hubSocket!
      ..add('not json at all')
      ..add(jsonEncode({'method': 'GET', 'path': '/api/boards'}))
      // A well-formed request: the next (and only) frame back must be its
      // response.
      ..add(jsonEncode({'id': 'req-1', 'method': 'GET', 'path': '/api/boards'}));

    final response = await frames.stream.first.timeout(
      const Duration(seconds: 15),
    );

    expect(response['id'], 'req-1');
    expect(response['status'], 200);
    expect(response['body'] as String, contains('Relay board'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
