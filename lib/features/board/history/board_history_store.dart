import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';

export 'board_history_store_vm.dart'
    if (dart.library.html) 'board_history_store_web.dart';

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

/// Web-safe file-system-like history store backed by [FileStorageAdapter].
///
/// On desktop this delegates to real files under the configured [rootPrefix].
/// On web it stores events in browser storage using scoped keys.
class AdapterBoardHistoryStore extends BoardHistoryStore {
  const AdapterBoardHistoryStore({this.rootPrefix = 'boards_history'});

  final String rootPrefix;

  String _eventsDir(String boardId) => p.join(
    rootPrefix,
    HistoryStoreHelpers.safeSegment(boardId),
    'events',
  );

  String _eventPath(BoardHistoryEvent event) => p.join(
    _eventsDir(event.boardId),
    '${event.timestamp.millisecondsSinceEpoch}_'
    '${HistoryStoreHelpers.safeSegment(event.opId)}.json',
  );

  @override
  Future<void> append(BoardHistoryEvent event) async {
    await FileStorageAdapter.instance.writeString(
      _eventPath(event),
      const JsonEncoder.withIndent('  ').convert(event.toJson()),
    );
  }

  @override
  Future<List<BoardHistoryEvent>> eventsForBoard(String boardId) async {
    final dir = _eventsDir(boardId);
    final storage = FileStorageAdapter.instance;
    if (!await storage.exists(dir)) return const [];

    final paths = await storage.list(dir);
    final events = <BoardHistoryEvent>[];
    for (final path in paths) {
      if (!path.endsWith('.json')) continue;
      final raw = await storage.readString(path);
      if (raw == null || raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          events.add(
            BoardHistoryEvent.fromJson(Map<String, dynamic>.from(decoded)),
          );
        }
      } catch (_) {
        // Ignore malformed entries.
      }
    }
    events.sort((a, b) {
      final byRevision = a.revision.compareTo(b.revision);
      if (byRevision != 0) return byRevision;
      return a.opId.compareTo(b.opId);
    });
    return events;
  }
}
