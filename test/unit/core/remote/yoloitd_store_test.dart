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
}
