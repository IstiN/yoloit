import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';

void main() {
  BoardHistoryEvent event({
    required String opId,
    required int revision,
    String boardId = 'board',
  }) {
    return BoardHistoryEvent(
      opId: opId,
      boardId: boardId,
      type: 'panel.updated',
      entityType: 'panel',
      entityId: 'panel-1',
      actorId: 'test',
      timestamp: DateTime.utc(2026, 5, 31, 12, revision),
      revision: revision,
      before: {'title': 'before-$revision'},
      after: {'title': 'after-$revision'},
    );
  }

  test('memory store filters and sorts board events', () async {
    final store = MemoryBoardHistoryStore();

    await store.append(event(opId: 'op-2', revision: 2));
    await store.append(event(opId: 'op-1', revision: 1));
    await store.append(event(opId: 'other', revision: 1, boardId: 'other'));

    final events = await store.eventsForBoard('board');

    expect(events.map((event) => event.opId), ['op-1', 'op-2']);
    expect(await store.eventById('board', 'op-2'), isNotNull);
    expect(await store.eventById('board', 'missing'), isNull);
  });

  test(
    'local store writes append-only json events and reads them sorted',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'board_history_store_',
      );
      addTearDown(() => tempDir.delete(recursive: true));
      final store = LocalBoardHistoryStore(rootPath: tempDir.path);

      await store.append(event(opId: 'op/2', revision: 2));
      await store.append(event(opId: 'op/1', revision: 1));

      final events = await store.eventsForBoard('board');

      expect(events.map((event) => event.revision), [1, 2]);
      expect(events.first.before, {'title': 'before-1'});
      expect(await store.eventById('board', 'op/2'), isNotNull);
    },
  );
}
