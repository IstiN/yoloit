import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';

class _FakeFileStorageAdapter implements FileStorageAdapter {
  final Map<String, String> files = {};

  @override
  Future<bool> exists(String path) async {
    if (files.containsKey(path)) return true;
    final prefix = '$path/';
    return files.keys.any((key) => key.startsWith(prefix));
  }

  @override
  Future<String?> readString(String path) async => files[path];

  @override
  Future<void> writeString(String path, String contents) async {
    files[path] = contents;
  }

  @override
  Future<List<String>> list(String directoryPath) async {
    return files.keys.where((key) => p.dirname(key) == directoryPath).toList();
  }

  @override
  Future<Uint8List?> readBytes(String path) => throw UnimplementedError();

  @override
  Future<void> appendString(String path, String contents) =>
      throw UnimplementedError();

  @override
  Future<int?> length(String path) => throw UnimplementedError();

  @override
  Future<void> writeBytes(String path, Uint8List bytes) =>
      throw UnimplementedError();

  @override
  Future<void> delete(String path) => throw UnimplementedError();
}

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

  group('AdapterBoardHistoryStore', () {
    test('returns empty when the events directory is missing', () async {
      final store = AdapterBoardHistoryStore(
        rootPrefix: '/root',
        storage: _FakeFileStorageAdapter(),
      );

      expect(await store.eventsForBoard('board'), isEmpty);
    });

    test('round-trips appended events sorted by revision then opId', () async {
      final storage = _FakeFileStorageAdapter();
      final store = AdapterBoardHistoryStore(
        rootPrefix: '/root',
        storage: storage,
      );

      await store.append(event(opId: 'op-z', revision: 2));
      await store.append(event(opId: 'op-b', revision: 1));
      await store.append(event(opId: 'op-a', revision: 1));
      await store.append(event(opId: 'op-x', revision: 1, boardId: 'other'));

      final events = await store.eventsForBoard('board');

      expect(events.map((event) => event.opId), ['op-a', 'op-b', 'op-z']);
      expect(events.first.after, {'title': 'after-1'});
      expect(
        storage.files.keys.every((path) => path.startsWith('/root/')),
        isTrue,
      );
      expect(await store.eventById('board', 'op-z'), isNotNull);
    });

    test('skips non-json, empty, malformed and non-map entries', () async {
      final storage = _FakeFileStorageAdapter();
      final store = AdapterBoardHistoryStore(
        rootPrefix: '/root',
        storage: storage,
      );

      await store.append(event(opId: 'op-1', revision: 1));
      const dir = '/root/board/events';
      storage.files[p.join(dir, 'notes.txt')] = '{"opId": "ignored"}';
      storage.files[p.join(dir, 'empty.json')] = '';
      storage.files[p.join(dir, 'broken.json')] = 'not json at all';
      storage.files[p.join(dir, 'list.json')] = '[1, 2, 3]';

      final events = await store.eventsForBoard('board');

      expect(events.map((event) => event.opId), ['op-1']);
    });
  });
}
