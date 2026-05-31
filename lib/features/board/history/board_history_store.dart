import 'dart:convert';
import 'dart:io';

import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';

abstract class BoardHistoryStore {
  const BoardHistoryStore();

  Future<void> append(BoardHistoryEvent event);

  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId);

  Future<BoardHistoryEvent?> eventById(String boardId, String opId) async {
    for (final event in await eventsForBoard(boardId)) {
      if (event.opId == opId) return event;
    }
    return null;
  }
}

class NoopBoardHistoryStore extends BoardHistoryStore {
  const NoopBoardHistoryStore();

  @override
  Future<void> append(BoardHistoryEvent event) async {}

  @override
  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId) async {
    return const [];
  }
}

class LocalBoardHistoryStore extends BoardHistoryStore {
  LocalBoardHistoryStore({String? rootPath})
    : rootPath =
          rootPath ??
          '${PlatformDirs.instance.dataDir}${Platform.pathSeparator}boards_history';

  final String rootPath;

  @override
  Future<void> append(BoardHistoryEvent event) async {
    final dir = Directory(
      [
        rootPath,
        _safeSegment(event.boardId),
        'events',
        event.timestamp.toUtc().year.toString().padLeft(4, '0'),
        event.timestamp.toUtc().month.toString().padLeft(2, '0'),
      ].join(Platform.pathSeparator),
    );
    await dir.create(recursive: true);
    final file = File(
      '${dir.path}${Platform.pathSeparator}'
      '${_safeSegment(event.opId)}_${_safeSegment(event.actorId)}.json',
    );
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(event.toJson()),
      flush: true,
    );
  }

  @override
  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId) async {
    final root = Directory(
      [rootPath, _safeSegment(boardId), 'events'].join(Platform.pathSeparator),
    );
    if (!await root.exists()) return const [];
    final events = <BoardHistoryEvent>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is Map) {
        events.add(
          BoardHistoryEvent.fromJson(Map<String, dynamic>.from(decoded)),
        );
      }
    }
    events.sort((a, b) {
      final byRevision = a.revision.compareTo(b.revision);
      if (byRevision != 0) return byRevision;
      return a.opId.compareTo(b.opId);
    });
    return events;
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }
}

class MemoryBoardHistoryStore extends BoardHistoryStore {
  final List<BoardHistoryEvent> events = [];

  @override
  Future<void> append(BoardHistoryEvent event) async {
    events.add(event);
  }

  @override
  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId) async {
    final result =
        events.where((event) => event.boardId == boardId).toList()
          ..sort((a, b) {
            final byRevision = a.revision.compareTo(b.revision);
            if (byRevision != 0) return byRevision;
            return a.opId.compareTo(b.opId);
          });
    return result;
  }
}
