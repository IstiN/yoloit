import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';

/// Desktop file-backed history store using `dart:io`.
///
/// Events are organized in year/month subdirectories for efficient browsing.
class LocalBoardHistoryStore extends BoardHistoryStore {
  LocalBoardHistoryStore({String? rootPath})
    : rootPath =
          rootPath ??
          '${PlatformDirs.instance.dataDir}${Platform.pathSeparator}boards_history';

  final String rootPath;

  @override
  Future<void> append(BoardHistoryEvent event) async {
    await HistoryStoreHelpers.appendEvent(
      rootPath: rootPath,
      boardId: event.boardId,
      timestamp: event.timestamp,
      opId: event.opId,
      actorId: event.actorId,
      json: event.toJson(),
    );
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
