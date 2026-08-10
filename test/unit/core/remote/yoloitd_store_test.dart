import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

void main() {
  test('store persists boards and undo restores resized panel', () async {
    final dir = await Directory.systemTemp.createTemp('yoloitd_store_');
    addTearDown(() => dir.delete(recursive: true));
    final store = YoloitdStore(rootDir: dir, actorId: 'test');
    await store.init();

    final board = await store.createBoard('Remote');
    final panel = await store.addPanel(
      board.id,
      const RemotePanel(
        id: 'shape-1',
        type: 'board.shape',
        title: 'Rhombus',
        bounds: RemotePanelBounds(x: 10, y: 20, width: 120, height: 120),
        state: {'shape': 'diamond'},
      ),
    );

    await store.updatePanel(
      board.id,
      panel.id,
      (panel) => panel.copyWith(
        bounds: panel.bounds.copyWith(width: 180, height: 140),
      ),
    );
    await store.updatePanel(
      board.id,
      panel.id,
      (panel) => panel.copyWith(
        bounds: panel.bounds.copyWith(width: 260, height: 180),
      ),
    );

    expect(await store.undoLatestPanelHistory(board.id), isTrue);

    final updated = await store.findBoard(board.id);
    final restored = updated!.panels.singleWhere(
      (panel) => panel.id == 'shape-1',
    );
    expect(restored.bounds.width, 120);
    expect(restored.bounds.height, 120);
    expect((await store.historyForBoard(board.id)).last.type, 'panel.restored');
  });

  group('YoloitdStore redo panel history', () {
    late Directory dir;
    late YoloitdStore store;
    late RemoteBoard board;

    const initialBounds =
        RemotePanelBounds(x: 10, y: 20, width: 120, height: 120);

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('yoloitd_store_redo_');
      store = YoloitdStore(rootDir: dir, actorId: 'test');
      await store.init();
      board = await store.createBoard('Remote');
      await store.addPanel(
        board.id,
        const RemotePanel(
          id: 'shape-1',
          type: 'board.shape',
          title: 'Rhombus',
          bounds: initialBounds,
          state: {'shape': 'diamond'},
        ),
      );
    });

    tearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });

    Future<RemotePanel> panel() async {
      final found = await store.findBoard(board.id);
      return found!.panels.singleWhere((entry) => entry.id == 'shape-1');
    }

    test('redo re-applies an undone panel resize', () async {
      await store.updatePanel(
        board.id,
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 260, height: 180),
        ),
      );

      expect(await store.undoLatestPanelHistory(board.id), isTrue);
      expect((await panel()).bounds.width, 120);

      expect(await store.redoLatestPanelHistory(board.id), isTrue);
      final redone = await panel();
      expect(redone.bounds.width, 260);
      expect(redone.bounds.height, 180);
      expect(store.redoDepthForBoard(board.id), 0);
    });

    test('redo re-adds the snapshot when the panel was removed after undo',
        () async {
      await store.updatePanel(
        board.id,
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 260, height: 180),
        ),
      );
      expect(await store.undoLatestPanelHistory(board.id), isTrue);

      // Drop the panel without recording history so the redo entry survives.
      expect(
        await store.removePanel(board.id, 'shape-1', recordHistory: false),
        isTrue,
      );
      final found = await store.findBoard(board.id);
      expect(found!.panels, isEmpty);

      expect(await store.redoLatestPanelHistory(board.id), isTrue);
      final readded = await panel();
      expect(readded.bounds.width, 260);
      expect(readded.state, {'shape': 'diamond'});
    });

    test('redo returns false when there is nothing to redo', () async {
      expect(await store.redoLatestPanelHistory(board.id), isFalse);
      expect(await store.redoLatestPanelHistory('no-such-board'), isFalse);
    });
  });
}
