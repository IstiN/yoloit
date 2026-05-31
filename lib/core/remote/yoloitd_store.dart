import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/yoloitd_models.dart';

class YoloitdStore {
  YoloitdStore({required this.rootDir, this.actorId = 'yoloitd'});

  final Directory rootDir;
  final String actorId;

  File get _boardsFile => File(p.join(rootDir.path, 'boards.json'));
  File get _activeFile => File(p.join(rootDir.path, 'active_board'));

  Future<void> init() async {
    await rootDir.create(recursive: true);
    final boards = await loadBoards();
    if (boards.isEmpty) {
      final board = _defaultBoard(name: 'Remote Board');
      await saveBoards(<RemoteBoard>[board], activeBoardId: board.id);
    }
  }

  Future<List<RemoteBoard>> loadBoards() async {
    if (!await _boardsFile.exists()) return const <RemoteBoard>[];
    final decoded = jsonDecode(await _boardsFile.readAsString());
    if (decoded is! List) return const <RemoteBoard>[];
    return decoded
        .whereType<Map<Object?, Object?>>()
        .map((entry) => RemoteBoard.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
  }

  Future<String?> activeBoardId() async {
    if (!await _activeFile.exists()) return null;
    final value = (await _activeFile.readAsString()).trim();
    return value.isEmpty ? null : value;
  }

  Future<void> saveBoards(
    List<RemoteBoard> boards, {
    required String? activeBoardId,
  }) async {
    await rootDir.create(recursive: true);
    await _writeJsonAtomic(
      _boardsFile,
      boards.map((board) => board.toJson()).toList(),
    );
    if (activeBoardId == null) {
      if (await _activeFile.exists()) await _activeFile.delete();
    } else {
      await _activeFile.writeAsString(activeBoardId, flush: true);
    }
  }

  Future<RemoteBoard> createBoard(String name) async {
    final boards = await loadBoards();
    final board = _defaultBoard(name: name);
    await saveBoards(<RemoteBoard>[...boards, board], activeBoardId: board.id);
    return board;
  }

  Future<RemoteBoard?> findBoard(String idOrName) async {
    final boards = await loadBoards();
    final byId = boards.where((board) => board.id == idOrName).firstOrNull;
    if (byId != null) return byId;
    final byName =
        boards
            .where(
              (board) => board.name.toLowerCase() == idOrName.toLowerCase(),
            )
            .firstOrNull;
    if (byName != null) return byName;
    return boards.where((board) => board.id.startsWith(idOrName)).firstOrNull;
  }

  Future<({RemoteBoard before, RemoteBoard after})?> updateBoard(
    String boardId,
    RemoteBoard Function(RemoteBoard board) update, {
    RemoteHistoryEvent Function(
      RemoteBoard before,
      RemoteBoard after,
      int revision,
    )?
    historyEvent,
  }) async {
    final boards = await loadBoards();
    final activeId = await activeBoardId();
    final index = boards.indexWhere((board) => board.id == boardId);
    if (index == -1) return null;
    final before = boards[index];
    var after = update(before);
    RemoteHistoryEvent? event;
    if (historyEvent != null &&
        jsonEncode(before.toJson()) != jsonEncode(after.toJson())) {
      final revision = before.historyRevision + 1;
      after = after.withHistoryRevision(revision);
      event = historyEvent(before, after, revision);
    }
    final next = <RemoteBoard>[...boards]..[index] = after;
    await saveBoards(next, activeBoardId: activeId ?? boardId);
    if (event != null) {
      await appendHistory(event);
    }
    return (before: before, after: after);
  }

  Future<void> deleteBoard(String boardId) async {
    final boards = await loadBoards();
    final activeId = await activeBoardId();
    final next = boards.where((board) => board.id != boardId).toList();
    final nextActive =
        activeId == boardId ? (next.isEmpty ? null : next.first.id) : activeId;
    await saveBoards(next, activeBoardId: nextActive);
  }

  Future<void> appendHistory(RemoteHistoryEvent event) async {
    final dir = Directory(
      p.join(
        rootDir.path,
        'boards_history',
        _safeSegment(event.boardId),
        'events',
        event.timestamp.toUtc().year.toString().padLeft(4, '0'),
        event.timestamp.toUtc().month.toString().padLeft(2, '0'),
      ),
    );
    await dir.create(recursive: true);
    final file = File(
      p.join(
        dir.path,
        '${_safeSegment(event.opId)}_${_safeSegment(event.actorId)}.json',
      ),
    );
    await _writeJsonAtomic(file, event.toJson());
  }

  Future<List<RemoteHistoryEvent>> historyForBoard(String boardId) async {
    final root = Directory(
      p.join(rootDir.path, 'boards_history', _safeSegment(boardId), 'events'),
    );
    if (!await root.exists()) return const <RemoteHistoryEvent>[];
    final events = <RemoteHistoryEvent>[];
    await for (final entity in root.list(recursive: true, followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final decoded = jsonDecode(await entity.readAsString());
      if (decoded is Map) {
        events.add(
          RemoteHistoryEvent.fromJson(Map<String, dynamic>.from(decoded)),
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

  Future<bool> undoLatestPanelHistory(String boardId) async {
    final board = await findBoard(boardId);
    if (board == null) return false;
    final events = await historyForBoard(board.id);

    for (var index = events.length - 1; index >= 0; index--) {
      final event = events[index];
      if (event.entityType != 'panel') continue;
      if (event.restoresOpId != null || event.type == 'panel.restored') {
        continue;
      }
      final current =
          board.panels.where((panel) => panel.id == event.entityId).firstOrNull;
      final before =
          event.before == null ? null : RemotePanel.fromJson(event.before!);
      final after =
          event.after == null ? null : RemotePanel.fromJson(event.after!);

      if (after != null &&
          before == null &&
          current != null &&
          _samePanel(current, after)) {
        await removePanel(board.id, after.id);
        return true;
      }
      if (before != null && current != null && !_samePanel(current, before)) {
        final start = _coalescedPanelUpdateStart(events, index);
        final snapshot =
            start.before == null ? before : RemotePanel.fromJson(start.before!);
        await restorePanel(board.id, snapshot, restoresOpId: event.opId);
        return true;
      }
      if (before != null && current == null && event.type == 'panel.deleted') {
        await restorePanel(board.id, before, restoresOpId: event.opId);
        return true;
      }
    }
    return false;
  }

  Future<RemotePanel> addPanel(String boardId, RemotePanel panel) async {
    late RemotePanel created;
    await updateBoard(
      boardId,
      (board) {
        final zIndex =
            board.panels
                .map((panel) => panel.zIndex)
                .fold<int>(0, (a, b) => a > b ? a : b) +
            1;
        created = panel.copyWith(
          zIndex: panel.zIndex == 0 ? zIndex : panel.zIndex,
        );
        return board.copyWith(panels: <RemotePanel>[...board.panels, created]);
      },
      historyEvent:
          (before, after, revision) => _event(
            boardId: boardId,
            type: 'panel.created',
            entityId: created.id,
            revision: revision,
            after: created.toJson(),
          ),
    );
    return created;
  }

  Future<RemotePanel?> updatePanel(
    String boardId,
    String panelId,
    RemotePanel Function(RemotePanel panel) update,
  ) async {
    RemotePanel? beforePanel;
    RemotePanel? afterPanel;
    await updateBoard(
      boardId,
      (board) {
        final panels = <RemotePanel>[];
        for (final panel in board.panels) {
          if (panel.id == panelId) {
            beforePanel = panel;
            afterPanel = update(panel);
            panels.add(afterPanel!);
          } else {
            panels.add(panel);
          }
        }
        return board.copyWith(panels: panels);
      },
      historyEvent:
          (before, after, revision) => _event(
            boardId: boardId,
            type: 'panel.updated',
            entityId: panelId,
            revision: revision,
            before: beforePanel?.toJson(),
            after: afterPanel?.toJson(),
            patch:
                beforePanel == null || afterPanel == null
                    ? const <String, dynamic>{}
                    : _panelPatch(beforePanel!, afterPanel!),
          ),
    );
    return afterPanel;
  }

  Future<bool> removePanel(String boardId, String panelId) async {
    RemotePanel? removed;
    await updateBoard(
      boardId,
      (board) {
        final panels = <RemotePanel>[];
        for (final panel in board.panels) {
          if (panel.id == panelId) {
            removed = panel;
          } else {
            panels.add(panel);
          }
        }
        return board.copyWith(
          panels: panels,
          links:
              board.links
                  .where(
                    (link) =>
                        link['fromPanelId'] != panelId &&
                        link['toPanelId'] != panelId &&
                        link['from'] != panelId &&
                        link['to'] != panelId,
                  )
                  .toList(),
        );
      },
      historyEvent:
          (before, after, revision) => _event(
            boardId: boardId,
            type: 'panel.deleted',
            entityId: panelId,
            revision: revision,
            before: removed?.toJson(),
          ),
    );
    return removed != null;
  }

  Future<void> restorePanel(
    String boardId,
    RemotePanel panel, {
    required String restoresOpId,
  }) async {
    await updateBoard(
      boardId,
      (board) {
        final panels = <RemotePanel>[];
        var replaced = false;
        for (final current in board.panels) {
          if (current.id == panel.id) {
            panels.add(panel);
            replaced = true;
          } else {
            panels.add(current);
          }
        }
        if (!replaced) panels.add(panel);
        return board.copyWith(panels: panels);
      },
      historyEvent:
          (before, after, revision) => _event(
            boardId: boardId,
            type: 'panel.restored',
            entityId: panel.id,
            revision: revision,
            after: panel.toJson(),
            restoresOpId: restoresOpId,
          ),
    );
  }

  RemoteHistoryEvent _event({
    required String boardId,
    required String type,
    required String entityId,
    required int revision,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic> patch = const <String, dynamic>{},
    String? restoresOpId,
  }) {
    return RemoteHistoryEvent(
      opId: _nextId('op'),
      boardId: boardId,
      type: type,
      entityType: 'panel',
      entityId: entityId,
      actorId: actorId,
      timestamp: DateTime.now().toUtc(),
      revision: revision,
      before: before,
      after: after,
      patch: patch,
      restoresOpId: restoresOpId,
    );
  }

  RemoteBoard _defaultBoard({required String name}) {
    return RemoteBoard(id: _nextId('board'), name: name);
  }

  static String _nextId(String prefix) {
    return '$prefix-${DateTime.now().microsecondsSinceEpoch}';
  }

  static Future<void> _writeJsonAtomic(File file, Object? value) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
    if (await file.exists()) {
      await file.delete();
    }
    await tmp.rename(file.path);
  }

  static String _safeSegment(String value) {
    return value.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  }

  static bool _samePanel(RemotePanel a, RemotePanel b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
  }

  static RemoteHistoryEvent _coalescedPanelUpdateStart(
    List<RemoteHistoryEvent> events,
    int latestIndex,
  ) {
    final latest = events[latestIndex];
    if (latest.type != 'panel.updated') return latest;
    var start = latestIndex;
    final signature = _patchSignature(latest);
    while (start > 0) {
      final previous = events[start - 1];
      if (previous.type != latest.type ||
          previous.entityType != latest.entityType ||
          previous.entityId != latest.entityId ||
          previous.restoresOpId != null ||
          previous.revision + 1 != events[start].revision ||
          _patchSignature(previous) != signature) {
        break;
      }
      start--;
    }
    return events[start];
  }

  static String _patchSignature(RemoteHistoryEvent event) {
    final keys = event.patch.keys.toList()..sort();
    return keys.join('|');
  }

  static Map<String, dynamic> _panelPatch(
    RemotePanel before,
    RemotePanel after,
  ) {
    final patch = <String, dynamic>{};
    void addIfChanged(String key, Object? beforeValue, Object? afterValue) {
      if (jsonEncode(beforeValue) != jsonEncode(afterValue)) {
        patch[key] = <String, dynamic>{
          'before': beforeValue,
          'after': afterValue,
        };
      }
    }

    addIfChanged('title', before.title, after.title);
    addIfChanged('bounds', before.bounds.toJson(), after.bounds.toJson());
    addIfChanged('color', before.color, after.color);
    addIfChanged('params', before.params, after.params);
    addIfChanged('zIndex', before.zIndex, after.zIndex);
    addIfChanged('hidden', before.hidden, after.hidden);
    addIfChanged('locked', before.locked, after.locked);
    addIfChanged('pinned', before.pinned, after.pinned);
    addIfChanged('state', before.state, after.state);
    return patch;
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
