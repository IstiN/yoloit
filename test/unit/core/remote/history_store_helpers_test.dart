import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yoloit_history_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('safeSegment', () {
    test('leaves safe characters unchanged', () {
      expect(HistoryStoreHelpers.safeSegment('abc123'), 'abc123');
      expect(HistoryStoreHelpers.safeSegment('test.file'), 'test.file');
      expect(HistoryStoreHelpers.safeSegment('foo-bar_baz'), 'foo-bar_baz');
    });

    test('replaces unsafe characters with underscore', () {
      expect(HistoryStoreHelpers.safeSegment('hello/world'), 'hello_world');
      expect(HistoryStoreHelpers.safeSegment('a@b#c'), 'a_b_c');
      expect(HistoryStoreHelpers.safeSegment('foo\\bar'), 'foo_bar');
    });
  });

  group('historyDirPath', () {
    test('builds correct path with year and month', () {
      final ts = DateTime(2024, 3, 15, 10, 30);
      final path = HistoryStoreHelpers.historyDirPath(
        '/tmp/root',
        'board-1',
        ts,
      );
      expect(path, p.join('/tmp/root', 'board-1', 'events', '2024', '03'));
    });

    test('zero-pads month', () {
      final ts = DateTime(2024, 1, 5);
      final path = HistoryStoreHelpers.historyDirPath(
        '/tmp/root',
        'board-1',
        ts,
      );
      expect(path, p.join('/tmp/root', 'board-1', 'events', '2024', '01'));
    });
  });

  group('historyFileName', () {
    test('formats file name correctly', () {
      final name = HistoryStoreHelpers.historyFileName('op-1', 'user-a');
      expect(name, 'op-1_user-a.json');
    });

    test('sanitizes unsafe characters', () {
      final name = HistoryStoreHelpers.historyFileName('op/1', 'user@a');
      expect(name, 'op_1_user_a.json');
    });
  });

  group('writeJsonAtomic', () {
    test('writes JSON atomically', () async {
      final file = File(p.join(tempDir.path, 'test.json'));
      await HistoryStoreHelpers.writeJsonAtomic(file, {'key': 'value'});

      expect(file.existsSync(), true);
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded['key'], 'value');
    });

    test('overwrites existing file', () async {
      final file = File(p.join(tempDir.path, 'test.json'));
      await file.writeAsString('old content');

      await HistoryStoreHelpers.writeJsonAtomic(file, {'new': 'data'});

      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded['new'], 'data');
    });
  });

  group('appendEvent', () {
    test('creates directory and writes event', () async {
      final rootPath = tempDir.path;
      final event = RemoteHistoryEvent(
        opId: 'op-1',
        boardId: 'board-1',
        type: 'create',
        entityType: 'panel',
        entityId: 'p1',
        actorId: 'user-a',
        timestamp: DateTime(2024, 3, 15, 10, 30),
        revision: 1,
      );

      await HistoryStoreHelpers.appendEvent(
        rootPath: rootPath,
        boardId: event.boardId,
        timestamp: event.timestamp,
        opId: event.opId,
        actorId: event.actorId,
        json: event.toJson(),
      );

      final expectedDir = Directory(
        p.join(rootPath, 'board-1', 'events', '2024', '03'),
      );
      expect(expectedDir.existsSync(), true);

      final expectedFile = File(
        p.join(expectedDir.path, 'op-1_user-a.json'),
      );
      expect(expectedFile.existsSync(), true);

      final content = await expectedFile.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      expect(decoded['opId'], 'op-1');
      expect(decoded['type'], 'create');
    });
  });

  group('loadHistoryEvents', () {
    test('returns empty list for non-existent directory', () async {
      final root = Directory(p.join(tempDir.path, 'nonexistent'));
      final events = await HistoryStoreHelpers.loadHistoryEvents<RemoteHistoryEvent>(
        root,
        (json) => RemoteHistoryEvent.fromJson(json),
      );
      expect(events, isEmpty);
    });

    test('loads and sorts events by revision then opId', () async {
      final root = Directory(p.join(tempDir.path, 'events'));
      await root.create(recursive: true);

      final event1 = RemoteHistoryEvent(
        opId: 'op-b',
        boardId: 'board-1',
        type: 'create',
        entityType: 'panel',
        entityId: 'p1',
        actorId: 'user-a',
        timestamp: DateTime(2024, 3, 15),
        revision: 2,
      );
      final event2 = RemoteHistoryEvent(
        opId: 'op-a',
        boardId: 'board-1',
        type: 'update',
        entityType: 'panel',
        entityId: 'p1',
        actorId: 'user-a',
        timestamp: DateTime(2024, 3, 15),
        revision: 1,
      );
      final event3 = RemoteHistoryEvent(
        opId: 'op-c',
        boardId: 'board-1',
        type: 'delete',
        entityType: 'panel',
        entityId: 'p1',
        actorId: 'user-a',
        timestamp: DateTime(2024, 3, 15),
        revision: 2,
      );

      for (final event in [event1, event2, event3]) {
        final file = File(p.join(root.path, '${event.opId}.json'));
        await HistoryStoreHelpers.writeJsonAtomic(file, event.toJson());
      }

      final events = await HistoryStoreHelpers.loadHistoryEvents<RemoteHistoryEvent>(
        root,
        (json) => RemoteHistoryEvent.fromJson(json),
      );

      expect(events.length, 3);
      expect(events[0].revision, 1);
      expect(events[1].revision, 2);
      expect(events[2].revision, 2);
      // Same revision sorted by opId
      expect(events[1].opId, 'op-b');
      expect(events[2].opId, 'op-c');
    });

    test('ignores non-JSON files', () async {
      final root = Directory(p.join(tempDir.path, 'events'));
      await root.create(recursive: true);

      final file = File(p.join(root.path, 'readme.txt'));
      await file.writeAsString('not json');

      final events = await HistoryStoreHelpers.loadHistoryEvents<RemoteHistoryEvent>(
        root,
        (json) => RemoteHistoryEvent.fromJson(json),
      );

      expect(events, isEmpty);
    });
  });
}
