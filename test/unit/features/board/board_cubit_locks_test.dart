import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  BoardCubit buildCubit(List<BoardDocument> boards) {
    final cubit = BoardCubit(
      historyStore: MemoryBoardHistoryStore(),
      actorId: 'tester',
    );
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(boards: boards, activeBoardId: 'local', isLoaded: true),
    );
    return cubit;
  }

  BoardDocument remoteBoardDoc({
    required String url,
    String remoteBoardId = 'remote-board',
    String? token,
  }) {
    return BoardDocument(
      id: 'remote',
      name: 'Remote',
      metadata: {
        'remote': {
          'url': url,
          'boardId': remoteBoardId,
          'token': ?token,
        },
      },
    );
  }

  BoardDocument remoteBoard(BoardCubit cubit) {
    return cubit.state.boards.firstWhere((board) => board.id == 'remote');
  }

  Map<String, dynamic> localLocks(BoardCubit cubit) {
    final locks = remoteBoard(cubit).metadata['panelLocks'];
    return locks is Map ? Map<String, dynamic>.from(locks) : {};
  }

  const lockablePanel = RemotePanel(
    id: 'panel-1',
    type: 'board.shape',
    title: 'Shape',
    bounds: RemotePanelBounds(x: 0, y: 0, width: 100, height: 100),
    state: <String, dynamic>{},
  );

  Future<({YoloitdStore store, YoloitdServer server, String url})>
  startServer() async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_locks_');
    addTearDown(() => dir.delete(recursive: true));
    final store = YoloitdStore(rootDir: dir, actorId: 'lock-test');
    final server = YoloitdServer(store: store, port: 0, token: 'secret');
    await server.start();
    addTearDown(server.stop);
    return (
      store: store,
      server: server,
      url: 'http://127.0.0.1:${server.boundPort}',
    );
  }

  test('returns false when the board does not exist', () async {
    final cubit = buildCubit(const [BoardDocument(id: 'local', name: 'Local')]);

    expect(await cubit.acquirePanelLock('missing', 'panel-1'), isFalse);
  });

  test('short-circuits for local boards without recording locks', () async {
    final cubit = buildCubit(const [BoardDocument(id: 'local', name: 'Local')]);

    expect(await cubit.acquirePanelLock('local', 'panel-1'), isTrue);
    expect(cubit.state.boards.single.metadata.containsKey('panelLocks'), isFalse);
  });

  test('acquires a remote lock and records it locally', () async {
    final env = await startServer();
    final remote = await env.store.createBoard('Lockable');
    await env.store.addPanel(remote.id, lockablePanel);
    final cubit = buildCubit([
      const BoardDocument(id: 'local', name: 'Local'),
      remoteBoardDoc(url: env.url, remoteBoardId: remote.id, token: 'secret'),
    ]);

    final before = DateTime.now().toUtc().millisecondsSinceEpoch;
    final acquired = await cubit.acquirePanelLock(
      'remote',
      'panel-1',
      ttlSec: 120,
    );

    expect(acquired, isTrue);
    final lock = localLocks(cubit)['panel-1'] as Map<String, dynamic>;
    expect(lock['actorId'], 'tester');
    expect(lock['expiresAt'] as int, greaterThan(before));

    final serverBoard = await env.store.findBoard(remote.id);
    final serverLocks = serverBoard!.metadata['panelLocks'] as Map;
    expect((serverLocks['panel-1'] as Map)['actorId'], 'tester');
  });

  test('surfaces a 409 conflict with the conflicting actor id', () async {
    final env = await startServer();
    final remote = await env.store.createBoard('Contended');
    await env.store.addPanel(remote.id, lockablePanel);
    await YoloitRemoteClient(
      baseUrl: env.url,
      token: 'secret',
    ).acquirePanelLock(remote.id, 'panel-1', actorId: 'someone-else');
    final cubit = buildCubit([
      const BoardDocument(id: 'local', name: 'Local'),
      remoteBoardDoc(url: env.url, remoteBoardId: remote.id, token: 'secret'),
    ]);

    final acquired = await cubit.acquirePanelLock('remote', 'panel-1');

    expect(acquired, isFalse);
    expect(cubit.state.panelLockConflictPanelId, 'panel-1');
    expect(cubit.state.panelLockConflictActorId, 'someone-else');
    expect(localLocks(cubit), isEmpty);
  });

  test('treats a non-409 remote error as a soft failure', () async {
    final env = await startServer();
    final cubit = buildCubit([
      const BoardDocument(id: 'local', name: 'Local'),
      remoteBoardDoc(
        url: env.url,
        remoteBoardId: 'no-such-board',
        token: 'secret',
      ),
    ]);

    final acquired = await cubit.acquirePanelLock('remote', 'panel-1');

    expect(acquired, isTrue);
    expect(localLocks(cubit)['panel-1'], isNotNull);
    expect(cubit.state.panelLockConflictPanelId, isNull);
  });

  test('falls back to a local lock when the server is unreachable', () async {
    final cubit = buildCubit([
      const BoardDocument(id: 'local', name: 'Local'),
      remoteBoardDoc(url: 'http://127.0.0.1:1'),
    ]);

    final acquired = await cubit.acquirePanelLock('remote', 'panel-1');

    expect(acquired, isTrue);
    expect(localLocks(cubit)['panel-1'], isNotNull);
  });

  test('handles a 409 conflict with a malformed body', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) {
      request.response.statusCode = 409;
      request.response.write('not-json');
      request.response.close();
    });
    final cubit = buildCubit([
      const BoardDocument(id: 'local', name: 'Local'),
      remoteBoardDoc(url: 'http://127.0.0.1:${server.port}'),
    ]);

    final acquired = await cubit.acquirePanelLock('remote', 'panel-1');

    expect(acquired, isFalse);
    expect(cubit.state.panelLockConflictPanelId, 'panel-1');
    expect(cubit.state.panelLockConflictActorId, isNull);
  });

  group('panelLockActor', () {
    BoardDocument boardWithLocks(Map<String, dynamic> locks) {
      return BoardDocument(
        id: 'b1',
        name: 'Board',
        metadata: {'panelLocks': locks},
      );
    }

    test('returns null when panelLocks metadata is not a map', () {
      final cubit = buildCubit(const [
        BoardDocument(id: 'b1', name: 'Board'),
      ]);
      expect(cubit.panelLockActor(cubit.state.boards.first, 'p1'), isNull);
    });

    test('returns null when the panel has no lock entry', () {
      final board = boardWithLocks({});
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });

    test('returns null when the lock entry is not a map', () {
      final board = boardWithLocks({'p1': 'bad-value'});
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });

    test('returns null when locked by the local actor', () {
      final board = boardWithLocks({
        'p1': {'actorId': 'tester', 'expiresAt': farFuture},
      });
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });

    test('returns the actor id for a valid non-expired remote lock', () {
      final board = boardWithLocks({
        'p1': {'actorId': 'someone-else', 'expiresAt': farFuture},
      });
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), 'someone-else');
    });

    test('returns null for an expired lock', () {
      final board = boardWithLocks({
        'p1': {'actorId': 'someone-else', 'expiresAt': 1},
      });
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });

    test('returns the actor id when expiresAt is not an int', () {
      final board = boardWithLocks({
        'p1': {'actorId': 'someone-else'},
      });
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), 'someone-else');
    });

    test('returns null when actorId is null', () {
      final board = boardWithLocks({
        'p1': {'expiresAt': farFuture},
      });
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });
  });

  group('_panelIdsLockedByActor', () {
    test('returns panel ids locked by a specific actor', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        metadata: {
          'panelLocks': {
            'p1': {'actorId': 'alice', 'expiresAt': farFuture},
            'p2': {'actorId': 'bob', 'expiresAt': farFuture},
            'p3': {'actorId': 'alice', 'expiresAt': farFuture},
          },
        },
      );
      final cubit = buildCubit([board]);

      // panelLockActor returns the actor id when the lock is held by a
      // non-local actor. 'tester' is the local actor in this cubit.
      expect(cubit.panelLockActor(board, 'p1'), 'alice');
      expect(cubit.panelLockActor(board, 'p2'), 'bob');
      expect(cubit.panelLockActor(board, 'p3'), 'alice');
    });

    test('skips expired locks', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        metadata: {
          'panelLocks': {
            'p1': {'actorId': 'alice', 'expiresAt': 1},
            'p2': {'actorId': 'alice', 'expiresAt': farFuture},
          },
        },
      );
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull); // expired
      expect(cubit.panelLockActor(board, 'p2'), 'alice'); // valid
    });

    test('skips non-map lock entries', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        metadata: {
          'panelLocks': {
            'p1': 'bad',
            'p2': {'actorId': 'alice', 'expiresAt': farFuture},
          },
        },
      );
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });

    test('returns empty set when metadata panelLocks is not a map', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        metadata: {'panelLocks': 'not-a-map'},
      );
      final cubit = buildCubit([board]);
      expect(cubit.panelLockActor(board, 'p1'), isNull);
    });
  });

  group('releasePanelLock', () {
    test('removes the lock for a local board', () async {
      final board = BoardDocument(
        id: 'local',
        name: 'Local',
        metadata: {
          'panelLocks': {
            'p1': {'actorId': 'tester', 'expiresAt': farFuture},
          },
        },
      );
      final cubit = buildCubit([board]);

      await cubit.releasePanelLock('local', 'p1');

      final locks = cubit.state.boards.first.metadata['panelLocks'] as Map;
      expect(locks.containsKey('p1'), isFalse);
    });

    test('is a no-op when the board does not exist', () async {
      final cubit = buildCubit(const [
        BoardDocument(id: 'local', name: 'Local'),
      ]);

      // Should not throw.
      await cubit.releasePanelLock('missing', 'p1');
    });

    test('is a no-op when the lock does not exist', () async {
      final board = BoardDocument(
        id: 'local',
        name: 'Local',
        metadata: {
          'panelLocks': <String, dynamic>{},
        },
      );
      final cubit = buildCubit([board]);

      await cubit.releasePanelLock('local', 'p1');

      final locks = cubit.state.boards.first.metadata['panelLocks'] as Map;
      expect(locks, isEmpty);
    });

    test('removes the lock from a remote board', () async {
      final env = await startServer();
      final remote = await env.store.createBoard('Release');
      await env.store.addPanel(remote.id, lockablePanel);
      final cubit = buildCubit([
        const BoardDocument(id: 'local', name: 'Local'),
        remoteBoardDoc(url: env.url, remoteBoardId: remote.id, token: 'secret'),
      ]);

      // Acquire then release.
      await cubit.acquirePanelLock('remote', 'panel-1', ttlSec: 120);
      expect(localLocks(cubit).containsKey('panel-1'), isTrue);

      await cubit.releasePanelLock('remote', 'panel-1');
      expect(localLocks(cubit).containsKey('panel-1'), isFalse);
    });
  });
}

/// A timestamp far enough in the future that locks won't be expired.
int get farFuture =>
    DateTime.now().toUtc().millisecondsSinceEpoch + 3600000;
