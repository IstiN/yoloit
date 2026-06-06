import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/remote/history_store_helpers.dart';
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
    final dirPath = HistoryStoreHelpers.historyDirPath(
      rootPath,
      event.boardId,
      event.timestamp,
    );
    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    final file = File(
      p.join(
        dirPath,
        HistoryStoreHelpers.historyFileName(event.opId, event.actorId),
      ),
    );
    await HistoryStoreHelpers.writeJsonAtomic(file, event.toJson());
  }

  @override
  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId) async {
    final root = Directory(
      p.join(rootPath, HistoryStoreHelpers.safeSegment(boardId), 'events'),
    );
    return HistoryStoreHelpers.loadHistoryEvents(
      root,
      BoardHistoryEvent.fromJson,
    );
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
