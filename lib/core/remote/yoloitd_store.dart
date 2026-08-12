import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/core/remote/panel_history_undo.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';

class YoloitdStore {
  YoloitdStore({required this.rootDir, this.actorId = 'yoloitd'});

  final Directory rootDir;
  final String actorId;
  final Map<String, List<_RemoteRedoEntry>> _redoStacks = {};
  bool _replayingHistory = false;

  // Debounced persistence — coalesces rapid saveBoards calls.
  Timer? _saveDebounce;
  List<RemoteBoard>? _pendingSaveBoards;
  String? _pendingSaveActiveBoardId;

  int redoDepthForBoard(String boardId) => _redoStacks[boardId]?.length ?? 0;

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

  // In-memory cache of boards — avoids re-reading + re-parsing JSON on every
  // findBoard/updateBoard/addPanel call (was 29.7K loadBoards calls in profile).
  List<RemoteBoard>? _boardsCache;

  Future<List<RemoteBoard>> loadBoards() async {
    final cached = _boardsCache;
    if (cached != null) return cached;
    if (!await _boardsFile.exists()) return const <RemoteBoard>[];
    final decoded = jsonDecode(await _boardsFile.readAsString());
    if (decoded is! List) return const <RemoteBoard>[];
    final boards = decoded
        .whereType<Map<Object?, Object?>>()
        .map((entry) => RemoteBoard.fromJson(Map<String, dynamic>.from(entry)))
        .toList();
    _boardsCache = boards;
    return boards;
  }

  String? _activeBoardIdCache;
  bool _activeBoardIdLoaded = false;

  Future<String?> activeBoardId() async {
    if (_activeBoardIdLoaded) return _activeBoardIdCache;
    if (!await _activeFile.exists()) {
      _activeBoardIdLoaded = true;
      _activeBoardIdCache = null;
      return null;
    }
    final value = (await _activeFile.readAsString()).trim();
    _activeBoardIdCache = value.isEmpty ? null : value;
    _activeBoardIdLoaded = true;
    return _activeBoardIdCache;
  }

  Future<void> saveBoards(
    List<RemoteBoard> boards, {
    required String? activeBoardId,
  }) async {
    // In debug mode, flush synchronously (tests need immediate persistence).
    if (kDebugMode) {
      _boardsCache = List.unmodifiable(boards);
      await _flushSaveBoards(boards, activeBoardId);
      return;
    }
    _pendingSaveBoards = boards;
    _pendingSaveActiveBoardId = activeBoardId;
    // Update cache immediately so subsequent loadBoards() calls see the new data.
    _boardsCache = List.unmodifiable(boards);
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 150), () {
      _flushSaveBoards(_pendingSaveBoards!, _pendingSaveActiveBoardId);
      _pendingSaveBoards = null;
      _pendingSaveActiveBoardId = null;
    });
  }

  Future<void> _flushSaveBoards(
    List<RemoteBoard> boards,
    String? activeBoardId,
  ) async {
    _activeBoardIdCache = activeBoardId;
    _activeBoardIdLoaded = true;
    await rootDir.create(recursive: true);
    await HistoryStoreHelpers.writeJsonAtomic(
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
    if (!_replayingHistory) {
      _redoStacks.remove(event.boardId);
    }
    await HistoryStoreHelpers.appendEvent(
      rootPath: p.join(rootDir.path, 'boards_history'),
      boardId: event.boardId,
      timestamp: event.timestamp,
      opId: event.opId,
      actorId: event.actorId,
      json: event.toJson(),
    );
  }

  Future<List<RemoteHistoryEvent>> historyForBoard(String boardId) async {
    final root = Directory(
      p.join(
        rootDir.path,
        'boards_history',
        HistoryStoreHelpers.safeSegment(boardId),
        'events',
      ),
    );
    return HistoryStoreHelpers.loadHistoryEvents(
      root,
      RemoteHistoryEvent.fromJson,
    );
  }

  Future<bool> undoLatestPanelHistory(String boardId) async {
    return _runHistoryReplay(() async {
      final board = await findBoard(boardId);
      if (board == null) return false;
      final events = await historyForBoard(board.id);

      final plan = planPanelHistoryUndo<RemotePanel>(
        events: events,
        currentPanelOf:
            (entityId) =>
                board.panels
                    .where((panel) => panel.id == entityId)
                    .firstOrNull,
        panelFromJson: RemotePanel.fromJson,
        panelToJson: (panel) => panel.toJson(),
        previousInRun:
            (previous, latest) => previous.type == latest.type,
      );

      switch (plan.kind) {
        case PanelUndoKind.none:
          return false;
        case PanelUndoKind.removeCreated:
          final after = plan.snapshot!;
          _pushRedo(board.id, _RemoteRedoEntry.recreate(after));
          await removePanel(board.id, after.id, recordHistory: false);
          return true;
        case PanelUndoKind.restoreSnapshot:
          final latestAfter = plan.redoSnapshot;
          if (latestAfter != null) {
            _pushRedo(board.id, _RemoteRedoEntry.restore(latestAfter));
          }
          await restorePanel(
            board.id,
            plan.snapshot!,
            restoresOpId: plan.opId!,
          );
          return true;
        case PanelUndoKind.restoreDeleted:
          _pushRedo(board.id, _RemoteRedoEntry.delete(plan.entityId!));
          await restorePanel(
            board.id,
            plan.snapshot!,
            restoresOpId: plan.opId!,
          );
          return true;
      }
    });
  }

  Future<bool> redoLatestPanelHistory(String boardId) async {
    final stack = _redoStacks[boardId];
    if (stack == null || stack.isEmpty) return false;
    final board = await findBoard(boardId);
    if (board == null) return false;

    final entry = stack.removeLast();
    if (stack.isEmpty) {
      _redoStacks.remove(boardId);
    }

    return _runHistoryReplay(() async {
      switch (entry.kind) {
        case _RemoteRedoKind.recreatePanel:
          final panel = entry.panel;
          if (panel == null) return false;
          await addPanel(board.id, panel);
          return true;
        case _RemoteRedoKind.restorePanel:
          final panel = entry.panel;
          if (panel == null) return false;
          return _applyPanelSnapshot(board.id, panel);
        case _RemoteRedoKind.deletePanel:
          final panelId = entry.panelId;
          if (panelId == null) return false;
          return removePanel(board.id, panelId);
      }
    });
  }

  Future<T> _runHistoryReplay<T>(Future<T> Function() action) async {
    _replayingHistory = true;
    try {
      return await action();
    } finally {
      _replayingHistory = false;
    }
  }

  void _pushRedo(String boardId, _RemoteRedoEntry entry) {
    final stack = _redoStacks.putIfAbsent(boardId, () => <_RemoteRedoEntry>[]);
    stack.add(entry);
  }

  Future<bool> _applyPanelSnapshot(String boardId, RemotePanel panel) async {
    final board = await findBoard(boardId);
    if (board == null) return false;
    final current =
        board.panels.where((entry) => entry.id == panel.id).firstOrNull;
    if (current != null && _samePanel(current, panel)) {
      return false;
    }
    if (current != null) {
      await updatePanel(boardId, panel.id, (_) => panel);
      return true;
    }
    await addPanel(boardId, panel);
    return true;
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

  Future<bool> removePanel(
    String boardId,
    String panelId, {
    bool recordHistory = true,
  }) async {
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
          recordHistory
              ? (before, after, revision) => _event(
                boardId: boardId,
                type: 'panel.deleted',
                entityId: panelId,
                revision: revision,
                before: removed?.toJson(),
              )
              : null,
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

  static bool _samePanel(RemotePanel a, RemotePanel b) {
    return jsonEncode(a.toJson()) == jsonEncode(b.toJson());
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

enum _RemoteRedoKind {
  recreatePanel,
  restorePanel,
  deletePanel,
}

class _RemoteRedoEntry {
  const _RemoteRedoEntry.recreate(this.panel)
    : kind = _RemoteRedoKind.recreatePanel,
      panelId = null;

  const _RemoteRedoEntry.restore(this.panel)
    : kind = _RemoteRedoKind.restorePanel,
      panelId = null;

  const _RemoteRedoEntry.delete(this.panelId)
    : kind = _RemoteRedoKind.deletePanel,
      panel = null;

  final _RemoteRedoKind kind;
  final RemotePanel? panel;
  final String? panelId;
}
