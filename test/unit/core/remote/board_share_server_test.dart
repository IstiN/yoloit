import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test('share server exposes local boards to remote clients', () async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    await cubit.load();
    await cubit.createBoard(name: 'Shared board');
    final sourceBoard = cubit.state.activeBoard!;

    final info = await BoardShareServer.instance.start(cubit, port: 0);
    addTearDown(BoardShareServer.instance.stop);

    final client = YoloitRemoteClient(
      baseUrl: 'http://127.0.0.1:${info.port}',
      token: info.token,
    );
    final boards = await client.listBoards();
    expect(boards.map((board) => board['id']), contains(sourceBoard.id));

    final remoteBoard = await client.fetchBoard(sourceBoard.id);
    expect(remoteBoard.name, 'Shared board');

    final renamed = await client.putBoard(
      remoteBoard.copyWith(
        name: 'Edited',
        viewport: const BoardViewport(scale: 0.4),
      ),
    );
    expect(renamed.name, 'Edited');
    expect(renamed.viewport.scale, 0.4);
    expect(cubit.state.activeBoard!.name, 'Edited');
    expect(cubit.state.activeBoard!.viewport.scale, sourceBoard.viewport.scale);
  });

  test(
    'share server exposes setup and filesystem APIs used by remote panels',
    () async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await cubit.load();

      final info = await BoardShareServer.instance.start(cubit, port: 0);
      addTearDown(BoardShareServer.instance.stop);

      final client = YoloitRemoteClient(
        baseUrl: 'http://127.0.0.1:${info.port}',
        token: info.token,
      );

      final setup = await client.setupCheck();
      expect(setup.packages, isNotEmpty);

      final listing = await client.listDirectory(Directory.current.path);
      expect(listing.path, Directory.current.path);
      expect(
        listing.entries.map((entry) => entry.name),
        contains('pubspec.yaml'),
      );

      final defaultListing = await client.listDirectory(null);
      final home =
          Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
      if (home != null && home.trim().isNotEmpty) {
        expect(defaultListing.path, home.trim());
        expect(
          defaultListing.roots.map((entry) => entry.name),
          contains('Home'),
        );
      }
    },
  );

  group('panel lock API', () {
    /// Bootstraps a [BoardCubit] with one board containing [panels], starts
    /// the share server, and returns the cubit, client, and created board.
    Future<({BoardCubit cubit, YoloitRemoteClient client, BoardDocument board})>
    _setup(List<BoardPanelInstance> panels) async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.createBoard(name: 'Lock board');
      for (final panel in panels) {
        await cubit.addPanel(panel);
      }
      final board = cubit.state.activeBoard!;

      final info = await BoardShareServer.instance.start(cubit, port: 0);
      addTearDown(BoardShareServer.instance.stop);

      final client = YoloitRemoteClient(
        baseUrl: 'http://127.0.0.1:${info.port}',
        token: info.token,
      );
      return (cubit: cubit, client: client, board: board);
    }

    Map<String, dynamic>? _panelLocks(BoardDocument board) {
      final raw = board.metadata['panelLocks'];
      return raw is Map ? Map<String, dynamic>.from(raw) : null;
    }

    test('acquire lock succeeds and stores panelLocks metadata', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final cubit = harness.cubit;
      final client = harness.client;
      final board = harness.board;

      await client.acquirePanelLock(
        board.id,
        'panel-1',
        actorId: 'actor-A',
        ttlSec: 60,
      );

      final updated = cubit.state.boards.firstWhere((b) => b.id == board.id);
      final locks = _panelLocks(updated);
      expect(locks, isNotNull);
      expect(locks!, contains('panel-1'));
      expect(locks['panel-1']['actorId'], 'actor-A');
    });

    test('acquire lock fails with 409 when another actor holds it', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final client = harness.client;
      final board = harness.board;

      await client.acquirePanelLock(
        board.id,
        'panel-1',
        actorId: 'actor-A',
      );

      expect(
        () => client.acquirePanelLock(board.id, 'panel-1', actorId: 'actor-B'),
        throwsA(
          isA<YoloitRemoteException>().having(
            (e) => e.statusCode,
            'statusCode',
            409,
          ),
        ),
      );
    });

    test('same actor can re-acquire an existing lock', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final client = harness.client;
      final board = harness.board;

      await client.acquirePanelLock(
        board.id,
        'panel-1',
        actorId: 'actor-A',
        ttlSec: 30,
      );
      // Re-locking as the same actor must not throw.
      await client.acquirePanelLock(
        board.id,
        'panel-1',
        actorId: 'actor-A',
        ttlSec: 120,
      );

      // Should not throw — if we reach here the test passes.
      expect(true, isTrue);
    });

    test('acquire lock fails with 400 when actorId is empty', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final client = harness.client;
      final board = harness.board;

      expect(
        () => client.acquirePanelLock(board.id, 'panel-1', actorId: ''),
        throwsA(
          isA<YoloitRemoteException>().having(
            (e) => e.statusCode,
            'statusCode',
            400,
          ),
        ),
      );
    });

    test('unlock releases the lock', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final cubit = harness.cubit;
      final client = harness.client;
      final board = harness.board;

      await client.acquirePanelLock(board.id, 'panel-1', actorId: 'actor-A');
      await client.releasePanelLock(board.id, 'panel-1');

      final updated = cubit.state.boards.firstWhere((b) => b.id == board.id);
      final locks = _panelLocks(updated);
      expect(locks == null || !locks.containsKey('panel-1'), isTrue);
    });

    test('GET on lock endpoint returns 405 method not allowed', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final info = BoardShareServer.instance.info!;
      final board = harness.board;

      final http = HttpClient();
      addTearDown(http.close);
      final request = await http.openUrl(
        'GET',
        Uri.parse(
          'http://127.0.0.1:${info.port}'
          '/api/boards/${Uri.encodeComponent(board.id)}'
          '/panels/panel-1/lock',
        ),
      );
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${info.token}',
      );
      final response = await request.close();
      final body = await utf8.decoder.bind(response).join();
      expect(response.statusCode, 405);
      expect(body, contains('method not allowed'));
    });

    test('locking a non-existent panel returns 404', () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-1',
          type: 'board.notes',
          title: 'Notes',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final client = harness.client;
      final board = harness.board;

      expect(
        () =>
            client.acquirePanelLock(board.id, 'no-such-panel', actorId: 'A'),
        throwsA(
          isA<YoloitRemoteException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
    });

    test('panel resolved by title (case-insensitive) when id does not match',
        () async {
      final harness = await _setup([
        BoardPanelInstance(
          id: 'panel-uuid-1',
          type: 'board.notes',
          title: 'My Panel',
          bounds: const BoardPanelBounds(
            x: 0,
            y: 0,
            width: 320,
            height: 220,
          ),
        ),
      ]);
      final cubit = harness.cubit;
      final client = harness.client;
      final board = harness.board;

      // Pass the lowercase title as the panel identifier — should resolve
      // to the panel via the case-insensitive title fallback.
      await client.acquirePanelLock(
        board.id,
        'my panel',
        actorId: 'actor-A',
      );

      final updated = cubit.state.boards.firstWhere((b) => b.id == board.id);
      final locks = _panelLocks(updated);
      expect(locks, isNotNull);
      expect(locks!, contains('my panel'));
    });
  });
}
