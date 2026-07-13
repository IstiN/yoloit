// Smoke test: the desktop app's real remote client (YoloitRemoteClient)
// against the Go yoloit-hub backend.
//
// By default the hub is spawned as a local process built from
// `remote/yoloit-hub`. To run against an already-deployed hub (e.g. Cloud
// Run), set the environment variables instead:
//   YOLOIT_HUB_SMOKE_URL=https://... YOLOIT_HUB_SMOKE_TOKEN=... \
//     flutter test test/integration/yoloit_hub_client_test.dart
// Proves contract compatibility with no client-side changes.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  late String baseUrl;
  late String token;

  Directory? workDir;
  Directory? dataDir;
  Process? hub;

  Future<int> _freePort() async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final p = socket.port;
    await socket.close();
    return p;
  }

  setUpAll(() async {
    // TestWidgetsFlutterBinding installs a mock HttpClient that 400s
    // everything; reset it so the test talks to the real hub.
    HttpOverrides.global = null;

    final envUrl = Platform.environment['YOLOIT_HUB_SMOKE_URL'];
    final envToken = Platform.environment['YOLOIT_HUB_SMOKE_TOKEN'];
    if (envUrl != null && envUrl.isNotEmpty) {
      // Deployed-hub mode: no local process, use the given endpoint.
      baseUrl = envUrl;
      token = envToken ?? '';
      return;
    }

    workDir = await Directory.systemTemp.createTemp('yoloit_hub_smoke_');
    dataDir = await Directory.systemTemp.createTemp('yoloit_hub_data_');

    // Build the hub binary from the repo checkout (tests run from repo root).
    final build = await Process.run('go', [
      'build',
      '-o',
      '${workDir!.path}/yoloit-hub',
      '.',
    ], workingDirectory: 'remote/yoloit-hub');
    expect(
      build.exitCode,
      0,
      reason: 'go build failed: ${build.stderr}',
    );

    token = 'it-token';
    final port = await _freePort();
    hub = await Process.start(
      '${workDir!.path}/yoloit-hub',
      const [],
      environment: {
        'YOLOIT_HUB_HOST': '127.0.0.1',
        'YOLOIT_HUB_PORT': '$port',
        'YOLOIT_HUB_DATA_DIR': dataDir!.path,
        'YOLOIT_HUB_TOKEN': token,
      },
    );
    baseUrl = 'http://127.0.0.1:$port';
    // Wait until the health endpoint answers.
    final probe = HttpClient();
    var up = false;
    for (var i = 0; i < 50 && !up; i++) {
      try {
        final req = await probe.getUrl(Uri.parse('$baseUrl/api/health'));
        req.headers.set('Authorization', 'Bearer $token');
        final res = await req.close();
        up = res.statusCode == 200;
        await res.drain<void>();
      } on Object {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    probe.close();
    expect(up, isTrue, reason: 'hub did not start on port $port');
  });

  tearDownAll(() async {
    hub?.kill();
    await workDir?.delete(recursive: true);
    await dataDir?.delete(recursive: true);
  });

  test('desktop client manages boards and panels on the Go hub', () async {
    final client = YoloitRemoteClient(baseUrl: baseUrl, token: token);

    final health = await client.health();
    expect(health['ok'], isTrue);

    // yoloitd/hub seed a default board in a fresh data dir — work relative
    // to the initial count instead of assuming emptiness.
    final initial = await client.listBoards();

    final created = await client.createBoard('Hub Smoke');
    final remote = remoteInfoForBoard(created);
    expect(remote, isNotNull);

    final boards = await client.listBoards();
    expect(boards, hasLength(initial.length + 1));

    // Fetch through the same path BoardCubit.connectRemoteBoards uses.
    final fetched = await client.fetchBoard(remote!.boardId);
    expect(fetched.name, 'Hub Smoke');
    expect(remoteInfoForBoard(fetched), isNotNull);

    // Add a panel locally and push a full snapshot (the app's write path).
    final withPanel = fetched.copyWith(
      panels: [
        ...fetched.panels,
        const BoardPanelInstance(
          id: 'smoke-note',
          type: 'board.note.markdown',
          title: 'Smoke Note',
          bounds: BoardPanelBounds(x: 40, y: 40, width: 320, height: 200),
          state: {'markdown': 'hello hub'},
        ),
      ],
    );
    final saved = await client.putBoard(withPanel);
    expect(saved.panels.any((p) => p.id == 'smoke-note'), isTrue);

    final refetched = await client.fetchBoard(remote.boardId);
    final note = refetched.panels.firstWhere((p) => p.id == 'smoke-note');
    expect(note.state['markdown'], 'hello hub');

    await client.deleteBoard(remote.boardId);
    expect(await client.listBoards(), hasLength(initial.length));
  });

  test('hub rejects wrong token with 401', () async {
    final bad = YoloitRemoteClient(baseUrl: baseUrl, token: 'wrong-token');
    await expectLater(bad.listBoards(), throwsA(anything));
  });
}
