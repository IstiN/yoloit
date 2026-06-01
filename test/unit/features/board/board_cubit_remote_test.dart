import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

void main() {
  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'connectRemoteBoards loads remote boards and syncs UI edits back',
    () async {
      final dir = await Directory.systemTemp.createTemp('yoloitd_cubit_');
      addTearDown(() => dir.delete(recursive: true));
      final store = YoloitdStore(rootDir: dir, actorId: 'remote-test');
      final remoteBoard = await store.createBoard('Remote UI');
      await store.addPanel(
        remoteBoard.id,
        const RemotePanel(
          id: 'shape-1',
          type: 'board.shape',
          title: 'Shape',
          bounds: RemotePanelBounds(x: 10, y: 20, width: 300, height: 220),
          state: {'shape': 'diamond'},
        ),
      );
      final server = YoloitdServer(store: store, port: 0, token: 'secret');
      await server.start();
      addTearDown(server.stop);

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await cubit.load();

      final boards = await cubit.connectRemoteBoards(
        url: 'http://127.0.0.1:${server.boundPort}',
        token: 'secret',
      );

      expect(boards, hasLength(greaterThanOrEqualTo(1)));
      final localRemote = cubit.state.activeBoard!;
      expect(localRemote.name, 'Remote UI');
      expect(localRemote.panels.single.title, 'Shape');

      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 260, height: 180),
        ),
      );
      await cubit.flushRemoteSync();

      final updated = await store.findBoard(remoteBoard.id);
      expect(updated!.panels.single.bounds.width, 260);
      expect(updated.panels.single.bounds.height, 180);

      final history = await store.historyForBoard(remoteBoard.id);
      expect(history.last.type, 'panel.updated');
      expect(history.last.entityId, 'shape-1');
    },
  );

  test(
    'remote sync refreshes instead of overwriting a newer server revision',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'yoloitd_cubit_conflict_',
      );
      addTearDown(() => dir.delete(recursive: true));
      final store = YoloitdStore(rootDir: dir, actorId: 'remote-test');
      final remoteBoard = await store.createBoard('Remote UI');
      await store.addPanel(
        remoteBoard.id,
        const RemotePanel(
          id: 'shape-1',
          type: 'board.shape',
          title: 'Shape',
          bounds: RemotePanelBounds(x: 10, y: 20, width: 300, height: 220),
          state: {'shape': 'diamond'},
        ),
      );
      final server = YoloitdServer(store: store, port: 0, token: 'secret');
      await server.start();
      addTearDown(server.stop);

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await cubit.load();
      await cubit.connectRemoteBoards(
        url: 'http://127.0.0.1:${server.boundPort}',
        token: 'secret',
      );

      await store.updatePanel(
        remoteBoard.id,
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 500, height: 280),
        ),
      );

      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 260, height: 180),
        ),
      );
      await cubit.flushRemoteSync();

      final serverBoard = await store.findBoard(remoteBoard.id);
      expect(serverBoard!.panels.single.bounds.width, 500);
      expect(cubit.state.activeBoard!.panels.single.bounds.width, 500);
    },
  );
}
