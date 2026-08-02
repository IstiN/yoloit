import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/panel_history_undo.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/utils/clipboard_utils.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/history/board_redo_entry.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_player_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';
import 'package:yoloit/features/board/services/board_operation_applier.dart';
import 'package:yoloit/features/board/services/board_panel_placement_utils.dart';
import 'package:yoloit/features/board/utils/board_grid_layout.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';


part 'board_cubit_panel_history.dart';
part 'board_cubit_locks.dart';

class BoardCubit extends Cubit<BoardState> {
  BoardCubit({
    BoardHistoryStore? historyStore,
    String actorId = 'local',
    ClipboardInterface? clipboard,
  }) : _historyStore = historyStore ?? const NoopBoardHistoryStore(),
       _actorId = actorId,
       _clipboard = clipboard ?? const SystemClipboard(),
       super(const BoardState()) {
    _boardEventSub = BoardEventBus.instance.stream.listen((event) {
      if (event is BoardToolMutationEvent) {
        _scheduleRemoteRefresh();
      }
    });
  }

  void _scheduleRemoteRefresh() {
    _remoteRefreshDebounce?.cancel();
    _remoteRefreshDebounce = Timer(const Duration(milliseconds: 250), () {
      unawaited(refreshRemoteBoards());
    });
  }

  void _startRemoteRefreshTimer() {
    final active = state.activeBoard;
    final isRemote = active != null && remoteInfoForBoard(active) != null;
    if (!isRemote) {
      _remoteRefreshTimer?.cancel();
      _remoteRefreshTimer = null;
      return;
    }
    if (_remoteRefreshTimer != null && _remoteRefreshTimer!.isActive) return;
    _remoteRefreshTimer?.cancel();
    _remoteRefreshTimer = Timer.periodic(_remoteRefreshInterval, (_) {
      unawaited(_onRemoteRefreshTick());
    });
  }

  Future<void> _onRemoteRefreshTick() async {
    if (_remoteRefreshInProgress) return;
    try {
      _remoteRefreshInProgress = true;
      await refreshRemoteBoards();
    } finally {
      _remoteRefreshInProgress = false;
    }
  }

  static const _boardsStorageKey = 'board.documents.v1';
  static const _activeBoardStorageKey = 'board.active.id.v1';

  final BoardHistoryStore _historyStore;
  final String _actorId;
  final ClipboardInterface _clipboard;
  bool _suppressRemoteSync = false;
  Timer? _remoteSyncDebounce;
  List<BoardDocument>? _pendingRemoteSyncBoards;
  List<BoardDocument>? _pendingRemoteSyncCurrentBoards;
  String? _pendingRemoteSyncActiveBoardId;
  bool _remoteSyncInFlight = false;
  Timer? _remoteRefreshDebounce;
  Timer? _remoteRefreshTimer;
  bool _remoteRefreshInProgress = false;
  static const _remoteRefreshInterval = Duration(milliseconds: 1200);
  StreamSubscription<BoardEvent>? _boardEventSub;
  final Map<String, BoardPanelInstance> _panelGestureStarts = {};
  final Map<String, List<BoardRedoEntry>> _redoStacks = {};
  bool _replayingHistory = false;


  Future<void> load() async {
    if (state.isLoaded) return;
    await AgentConfigService.instance.load();
    final prefs = await SharedPreferences.getInstance();
    final rawBoards = prefs.getString(_boardsStorageKey);
    final rawActiveId = prefs.getString(_activeBoardStorageKey);

    List<BoardDocument> boards;
    if (rawBoards == null || rawBoards.isEmpty) {
      boards = [_buildDefaultBoard(name: 'Board 1')];
      await _persist(boards: boards, activeBoardId: boards.first.id);
    } else {
      final decoded = jsonDecode(rawBoards) as List<dynamic>;
      boards =
          decoded
              .map(
                (entry) => BoardDocument.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList();
      // Deduplicate panels that share the same ID (caused by a prior
      // escaped-interpolation bug in onCreateLinkedPanel).
      var needsResave = false;
      boards =
          boards.map((board) {
            final seen = <String>{};
            final unique = <BoardPanelInstance>[];
            for (final p in board.panels) {
              if (seen.add(p.id)) {
                unique.add(p);
              } else {
                needsResave = true;
              }
            }
            // Also remove links referencing deleted panels.
            final ids = unique.map((p) => p.id).toSet();
            final validLinks =
                board.links
                    .where(
                      (l) =>
                          ids.contains(l.fromPanelId) &&
                          ids.contains(l.toPanelId),
                    )
                    .toList();
            if (unique.length != board.panels.length ||
                validLinks.length != board.links.length) {
              return board.copyWith(panels: unique, links: validLinks);
            }
            return board;
          }).toList();
      if (needsResave) {
        assert(() {
          debugPrint('[BoardCubit] removed duplicate-ID panels, re-saving');
          return true;
        }());
        await _persist(boards: boards, activeBoardId: rawActiveId);
      }
      if (boards.isEmpty) {
        boards = [_buildDefaultBoard(name: 'Board 1')];
        await _persist(boards: boards, activeBoardId: boards.first.id);
      }
    }

    final activeBoardId =
        boards.any((board) => board.id == rawActiveId)
            ? rawActiveId
            : boards.first.id;

    emit(
      BoardState(boards: boards, activeBoardId: activeBoardId, isLoaded: true),
    );
  }

  Future<BoardDocument?> createBoard({String? name}) async {
    final current = state.boards;
    if (current.isEmpty && !state.isLoaded) return null;
    final board = _buildDefaultBoard(name: _nextBoardName(name));
    final updated = [...current, board];
    await _setBoards(updated, activeBoardId: board.id);
    return board;
  }

  /// Creates a board and applies a list of `board:apply`-style operations to it.
  ///
  /// This is used by the template system to instantiate a board from a
  /// parameterized template.
  Future<BoardDocument?> createBoardFromOperations({
    String? name,
    required List<Map<String, dynamic>> operations,
  }) async {
    final board = await createBoard(name: name);
    if (board == null) return null;
    const applier = BoardOperationApplier();
    return applier.apply(this, board, operations);
  }

  Future<List<BoardDocument>> connectRemoteBoards({
    required String url,
    String? token,
  }) async {
    final client = YoloitRemoteClient(baseUrl: url, token: token);
    await client.health();
    final summaries = await client.listBoards();
    final remoteBoards = <BoardDocument>[];
    for (final summary in summaries) {
      final id = summary['id'] as String?;
      if (id == null || id.trim().isEmpty) continue;
      remoteBoards.add(await client.fetchBoard(id));
    }
    if (remoteBoards.isEmpty) {
      remoteBoards.add(await client.createBoard('Remote Board'));
    }

    final remoteIds = remoteBoards.map((board) => board.id).toSet();
    final retained =
        state.boards.where((board) {
          final remote = remoteInfoForBoard(board);
          if (remote == null) return true;
          if (remote.url != client.baseUri.toString()) return true;
          return remoteIds.contains(board.id);
        }).toList();
    final merged = <BoardDocument>[
      ...retained.where((board) => !remoteIds.contains(board.id)),
      ...remoteBoards,
    ];
    _suppressRemoteSync = true;
    try {
      await _setBoards(merged, activeBoardId: remoteBoards.first.id);
    } finally {
      _suppressRemoteSync = false;
    }
    return remoteBoards;
  }

  Future<void> refreshRemoteBoards({String? url}) async {
    final remoteBoards =
        state.boards.where((board) {
          final remote = remoteInfoForBoard(board);
          if (remote == null) return false;
          return url == null || remote.url == url;
        }).toList();
    if (remoteBoards.isEmpty) return;

    final refreshed = <String, BoardDocument>{};
    for (final board in remoteBoards) {
      final remote = remoteInfoForBoard(board)!;
      final client = YoloitRemoteClient(
        baseUrl: remote.url,
        token: remote.token,
      );
      final fetched = await client.fetchBoard(
        remote.boardId,
        viewportOverride: board.viewport,
      );
      refreshed[board.id] = _mergeRemoteBoard(board, fetched);
    }
    final next = state.boards
        .map((board) => refreshed[board.id] ?? board)
        .toList(growable: false);
    _suppressRemoteSync = true;
    try {
      await _setBoards(next, activeBoardId: state.activeBoardId);
    } finally {
      _suppressRemoteSync = false;
    }
  }

  BoardDocument _mergeRemoteBoard(
    BoardDocument local,
    BoardDocument remote,
  ) {
    final lockedIds = _panelIdsLockedByActor(local, _actorId);
    final localById = {for (final panel in local.panels) panel.id: panel};
    final remoteById = {for (final panel in remote.panels) panel.id: panel};
    final mergedPanels = <BoardPanelInstance>[];
    for (final panel in remote.panels) {
      if (lockedIds.contains(panel.id) && localById.containsKey(panel.id)) {
        mergedPanels.add(localById[panel.id]!);
      } else {
        mergedPanels.add(panel);
      }
    }
    for (final panel in local.panels) {
      if (!remoteById.containsKey(panel.id)) {
        mergedPanels.add(panel);
      }
    }
    return remote.copyWith(panels: mergedPanels, viewport: local.viewport);
  }

  Future<void> disconnectRemoteBoard(String boardId) async {
    final board =
        state.boards.where((entry) => entry.id == boardId).firstOrNull;
    if (board == null || remoteInfoForBoard(board) == null) return;
    await _disconnectRemoteBoards((entry) => entry.id == boardId);
  }

  Future<void> deleteRemoteBoardOnServer(String boardId) async {
    final board =
        state.boards.where((entry) => entry.id == boardId).firstOrNull;
    final remote = board == null ? null : remoteInfoForBoard(board);
    if (remote == null) return;
    final client = YoloitRemoteClient(baseUrl: remote.url, token: remote.token);
    await client.deleteBoard(remote.boardId);
    await _disconnectRemoteBoards((entry) => entry.id == boardId);
  }

  Future<void> disconnectRemoteBoardsForUrl(String url) async {
    await _disconnectRemoteBoards((entry) {
      final remote = remoteInfoForBoard(entry);
      return remote != null && remote.url == url;
    });
  }

  Future<void> _disconnectRemoteBoards(
    bool Function(BoardDocument) remove,
  ) async {
    if (state.boards.isEmpty) return;
    final removed = state.boards.where(remove).toList(growable: false);
    if (removed.isEmpty) return;
    for (final board in removed) {
      for (final panel in board.panels) {
        WebViewManager.instance.remove(panel.id);
      }
    }
    var updated = state.boards.where((board) => !remove(board)).toList();
    String? activeBoardId = state.activeBoardId;
    if (updated.isEmpty) {
      final replacement = _buildDefaultBoard(name: 'Board 1');
      updated = [replacement];
      activeBoardId = replacement.id;
    } else if (activeBoardId == null ||
        !updated.any((board) => board.id == activeBoardId)) {
      activeBoardId = updated.first.id;
    }
    _suppressRemoteSync = true;
    try {
      await _setBoards(updated, activeBoardId: activeBoardId);
    } finally {
      _suppressRemoteSync = false;
    }
  }

  Future<List<BoardHistoryEvent>> historyForBoard(String boardId) {
    return _historyStore.eventsForBoard(boardId);
  }

  Future<bool> restorePanelFromEvent(String boardId, String opId) async {
    final event = await _historyStore.eventById(boardId, opId);
    if (event == null || event.entityType != 'panel') return false;
    final snapshot = event.before ?? event.after;
    if (snapshot == null) return false;
    return _restorePanelSnapshot(
      boardId: boardId,
      panelFromEvent: _panelFromHistorySnapshot(snapshot),
      restoresOpId: opId,
    );
  }

  Future<bool> _restorePanelSnapshot({
    required String boardId,
    required BoardPanelInstance panelFromEvent,
    required String restoresOpId,
  }) async {
    var restored = false;
    await _updateBoard(
      boardId,
      (board) {
        final existingIndex = board.panels.indexWhere(
          (panel) => panel.id == panelFromEvent.id,
        );
        if (existingIndex != -1 &&
            board.panels[existingIndex] == panelFromEvent) {
          return board;
        }
        if (existingIndex != -1) {
          restored = true;
          final panels = [...board.panels];
          panels[existingIndex] = panelFromEvent;
          return board.copyWith(
            panels: panels,
            viewport: board.viewport.copyWith(
              focusedPanelId: panelFromEvent.id,
            ),
          );
        }
        restored = true;
        final maxZ = board.panels.fold<int>(
          0,
          (value, panel) => panel.zIndex > value ? panel.zIndex : value,
        );
        return board.copyWith(
          panels: [...board.panels, panelFromEvent.copyWith(zIndex: maxZ + 1)],
          viewport: board.viewport.copyWith(focusedPanelId: panelFromEvent.id),
        );
      },
      historyEvent: (before, after, revision) {
        final beforePanel = before.panels.firstWhereOrNull(
          (panel) => panel.id == panelFromEvent.id,
        );
        return _historyEvent(
          boardId: boardId,
          type: 'panel.restored',
          entityType: 'panel',
          entityId: panelFromEvent.id,
          revision: revision,
          before: beforePanel == null ? null : _panelSnapshot(beforePanel),
          after: _panelSnapshot(
            after.panels.firstWhere((panel) => panel.id == panelFromEvent.id),
          ),
          restoresOpId: restoresOpId,
        );
      },
    );
    return restored;
  }

  Future<void> setActiveBoard(String id) async {
    if (!state.boards.any((board) => board.id == id)) return;
    await _setBoards(state.boards, activeBoardId: id);
    emit(state.copyWith(clearSelection: true));
    _startRemoteRefreshTimer();
  }

  Future<void> renameBoard(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _updateBoard(
      id,
      (board) => board.copyWith(name: trimmed),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: id,
            type: 'board.renamed',
            entityType: 'board',
            entityId: id,
            revision: revision,
            before: {'name': before.name},
            after: {'name': after.name},
          ),
    );
  }

  Future<void> updateBoardDefaultFolder(
    String id,
    String? defaultFolder,
  ) async {
    await _updateBoard(
      id,
      (board) {
        final trimmed = defaultFolder?.trim() ?? '';
        final metadata = Map<String, dynamic>.from(board.metadata);
        if (trimmed.isEmpty) {
          metadata.remove('defaultFolder');
        } else {
          metadata['defaultFolder'] = trimmed;
        }
        return board.copyWith(metadata: metadata);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: id,
            type: 'board.metadataUpdated',
            entityType: 'board',
            entityId: id,
            revision: revision,
            before: {'metadata': before.metadata},
            after: {'metadata': after.metadata},
          ),
    );
  }

  Future<BoardDocument?> replaceBoardSnapshotFromShare(
    BoardDocument snapshot,
  ) async {
    final boards = state.boards;
    final index = boards.indexWhere((board) => board.id == snapshot.id);
    if (index == -1) return null;

    final before = boards[index];
    final revision = _historyRevision(before) + 1;
    final metadata =
        Map<String, dynamic>.from(snapshot.metadata)
          ..remove('remote')
          ..remove('remoteSource')
          ..['historyRevision'] = revision;
    final after = snapshot.copyWith(metadata: metadata);
    final updated = [...boards]..[index] = after;

    await _setBoards(updated, activeBoardId: state.activeBoardId ?? after.id);
    await _appendHistory(
      _historyEvent(
        boardId: after.id,
        type: 'board.sharedSnapshotUpdated',
        entityType: 'board',
        entityId: after.id,
        revision: revision,
        before: before.toJson(),
        after: after.toJson(),
      ),
    );
    return after;
  }

  Future<void> deleteBoard(String id) async {
    if (state.boards.isEmpty) return;
    final board = state.boards.where((entry) => entry.id == id).firstOrNull;
    if (board != null) {
      for (final panel in board.panels) {
        WebViewManager.instance.remove(panel.id);
      }
    }
    final updated = state.boards.where((board) => board.id != id).toList();
    if (updated.isEmpty) {
      final replacement = _buildDefaultBoard(name: 'Board 1');
      await _setBoards([replacement], activeBoardId: replacement.id);
      return;
    }
    final nextActive =
        state.activeBoardId == id ? updated.first.id : state.activeBoardId;
    await _setBoards(updated, activeBoardId: nextActive);
  }

  Future<void> archiveBoard(String id) async {
    final isActive = state.activeBoardId == id;
    await _updateBoard(id, (board) => board.copyWith(archived: true));
    if (isActive) {
      final next = state.activeBoards.firstOrNull;
      if (next != null) {
        await setActiveBoard(next.id);
      }
    }
  }

  Future<void> unarchiveBoard(String id) async {
    await _updateBoard(id, (board) => board.copyWith(archived: false));
  }

  Future<void> updateViewport(BoardViewport viewport, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) => board.copyWith(viewport: viewport));
  }

  Future<void> focusPanel(
    String panelId, {
    String? boardId,
    bool zoomOnFocus = false,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (kDebugMode) {
      debugPrint('[BoardCubit] focusPanel panelId=$panelId targetId=$targetId stateActiveBoardId=${state.activeBoard?.id}');
    }
    if (targetId == null) return;
    final previousBoard = state.boards.firstWhereOrNull((b) => b.id == targetId);
    if (previousBoard != null) {
      final previousLocks = _panelIdsLockedByActor(previousBoard, _actorId)
          .where((id) => id != panelId);
      for (final id in previousLocks) {
        await releasePanelLock(targetId, id);
      }
      final acquired = await acquirePanelLock(targetId, panelId);
      if (!acquired) return;
      _startPanelLockRenewal(targetId, panelId);
    }
    await _updateBoard(targetId, (board) {
      final maxZ = board.panels.fold<int>(
        0,
        (value, panel) => panel.zIndex > value ? panel.zIndex : value,
      );
      BoardPanelInstance? focusedPanel;
      for (final panel in board.panels) {
        if (panel.id == panelId) {
          focusedPanel = panel;
          break;
        }
      }
      final alreadyTopAndFocused =
          board.viewport.focusedPanelId == panelId &&
          focusedPanel != null &&
          focusedPanel.zIndex >= maxZ &&
          !zoomOnFocus; // always re-focus if zoom requested
      if (kDebugMode) {
        debugPrint('[BoardCubit] focusPanel alreadyTopAndFocused=$alreadyTopAndFocused boardViewportFocusedPanelId=${board.viewport.focusedPanelId}');
      }
      if (alreadyTopAndFocused) {
        return board;
      }
      final updatedPanels =
          board.panels
              .map(
                (panel) =>
                    panel.id == panelId
                        ? panel.copyWith(zIndex: maxZ + 1)
                        : panel,
              )
              .toList();
      return board.copyWith(
        panels: updatedPanels,
        viewport: board.viewport.copyWith(
          focusedPanelId: panelId,
          zoomOnFocus: zoomOnFocus,
        ),
      );
    });
  }

  void openYoloAssistant(String panelId, {bool startMic = false}) {
    emit(
      state.copyWith(
        yoloAssistantAnchorPanelId: panelId,
        yoloAssistantStartMic: startMic,
      ),
    );
  }

  void closeYoloAssistant() {
    if (state.yoloAssistantAnchorPanelId == null &&
        !state.yoloAssistantStartMic) {
      return;
    }
    emit(
      state.copyWith(
        clearYoloAssistantAnchor: true,
        yoloAssistantStartMic: false,
      ),
    );
  }

  void consumeYoloAssistantStartMic() {
    if (!state.yoloAssistantStartMic) return;
    emit(state.copyWith(yoloAssistantStartMic: false));
  }

  /// Clears the zoom-on-focus flag after it has been consumed by the view.
  Future<void> clearZoomFocus({String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      if (!board.viewport.zoomOnFocus) return board;
      return board.copyWith(
        viewport: board.viewport.copyWith(zoomOnFocus: false),
      );
    });
  }

  Future<void> clearFocusedPanel({String? boardId}) async {
    _stopPanelLockRenewal();
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    final board = state.boards.firstWhereOrNull((b) => b.id == targetId);
    final locks = board == null
        ? <String>{}
        : _panelIdsLockedByActor(board, _actorId);
    await _updateBoard(targetId, (board) {
      if (board.viewport.focusedPanelId == null) {
        return board;
      }
      return board.copyWith(
        viewport: board.viewport.copyWith(clearFocusedPanelId: true),
      );
    });
    for (final panelId in locks) {
      unawaited(releasePanelLock(targetId, panelId));
    }
  }

  // ── Grid view ─────────────────────────────────────────────────────────────

  static const _gridSnapshotKey = 'gridViewSnapshot';

  Map<String, dynamic> _snapshotPanelBounds(List<BoardPanelInstance> panels) {
    return {for (final panel in panels) panel.id: panel.bounds.toJson()};
  }

  BoardHistoryEvent _gridModeHistoryEvent(
    String boardId,
    String type,
    BoardDocument before,
    BoardDocument after,
    int revision,
  ) {
    return _historyEvent(
      boardId: boardId,
      type: type,
      entityType: 'board',
      entityId: boardId,
      revision: revision,
      before: before.gridMode.toJson(),
      after: after.gridMode.toJson(),
    );
  }

  Future<void> setGridMode(String boardId, {required bool enabled}) async {
    await _updateBoard(
      boardId,
      (board) {
        final current = board.gridMode;
        if (current.enabled == enabled) return board;
        var next = board.copyWithGridMode(current.copyWith(enabled: enabled));
        final metadata = Map<String, dynamic>.from(next.metadata);
        if (enabled) {
          metadata[_gridSnapshotKey] = _snapshotPanelBounds(board.panels);
          next = next.copyWith(
            metadata: metadata,
            panels: arrangePanelsInCloud(next.gridMode, next.panels),
          );
        } else {
          final snapshot = metadata[_gridSnapshotKey] as Map<String, dynamic>?;
          if (snapshot != null) {
            final restoredPanels =
                next.panels.map((panel) {
                  final raw = snapshot[panel.id];
                  if (raw is Map<String, dynamic>) {
                    return panel.copyWith(
                      bounds: BoardPanelBounds.fromJson(raw),
                    );
                  }
                  return panel;
                }).toList();
            next = next.copyWith(panels: restoredPanels);
          }
          metadata.remove(_gridSnapshotKey);
          next = next.copyWith(metadata: metadata);
        }
        return next;
      },
      historyEvent:
          (before, after, revision) => _gridModeHistoryEvent(
            boardId,
            'board.gridModeChanged',
            before,
            after,
            revision,
          ),
    );
  }

  Future<void> setGridCellSize(String boardId, double cellSize) async {
    if (cellSize < 40) return;
    await _updateBoard(
      boardId,
      (board) {
        final nextMode = board.gridMode.copyWith(cellSize: cellSize);
        final snapped =
            board.panels
                .map((panel) => snapPanelToGrid(nextMode, panel))
                .toList();
        return board.copyWithGridMode(nextMode).copyWith(panels: snapped);
      },
      historyEvent:
          (before, after, revision) => _gridModeHistoryEvent(
            boardId,
            'board.gridCellSizeChanged',
            before,
            after,
            revision,
          ),
    );
  }

  Future<void> setGridSpacing(String boardId, double spacing) async {
    if (spacing < 0) return;
    await _updateBoard(
      boardId,
      (board) {
        final nextMode = board.gridMode.copyWith(spacing: spacing);
        final snapped =
            board.panels
                .map((panel) => snapPanelToGrid(nextMode, panel))
                .toList();
        return board.copyWithGridMode(nextMode).copyWith(panels: snapped);
      },
      historyEvent:
          (before, after, revision) => _gridModeHistoryEvent(
            boardId,
            'board.gridSpacingChanged',
            before,
            after,
            revision,
          ),
    );
  }

  Future<void> arrangePanelsInGrid(String boardId) async {
    await _updateBoard(
      boardId,
      (board) => board.copyWith(
        panels: arrangePanelsInCloud(board.gridMode, board.panels),
      ),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'board.gridArranged',
            entityType: 'board',
            entityId: boardId,
            revision: revision,
            before: {'panelCount': before.panels.length},
            after: {'panelCount': after.panels.length},
          ),
    );
  }

  Future<void> arrangePanelsByTypeInGrid(String boardId) async {
    await _updateBoard(
      boardId,
      (board) => board.copyWith(
        panels: arrangePanelsByType(board.gridMode, board.panels),
      ),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'board.gridArrangedByType',
            entityType: 'board',
            entityId: boardId,
            revision: revision,
            before: {'panelCount': before.panels.length},
            after: {'panelCount': after.panels.length},
          ),
    );
  }

  /// Re-snaps the current grid layout to the default cloud arrangement.
  ///
  /// If grid mode is off, it is enabled first and a freeform snapshot is saved.
  /// If a snapshot already exists, the cloud is recomputed from those original
  /// freeform positions so repeated resets are deterministic.
  Future<void> resetGridView(String boardId) async {
    await _updateBoard(
      boardId,
      (board) {
        final metadata = Map<String, dynamic>.from(board.metadata);
        var next = board;
        if (!next.gridMode.enabled) {
          metadata[_gridSnapshotKey] = _snapshotPanelBounds(next.panels);
          next = next.copyWithGridMode(next.gridMode.copyWith(enabled: true));
        }

        final snapshot = metadata[_gridSnapshotKey] as Map<String, dynamic>?;
        final basePanels =
            snapshot == null
                ? next.panels
                : next.panels.map((panel) {
                  final raw = snapshot[panel.id];
                  if (raw is Map<String, dynamic>) {
                    return panel.copyWith(
                      bounds: BoardPanelBounds.fromJson(raw),
                    );
                  }
                  return panel;
                }).toList();

        next = next.copyWith(
          metadata: metadata,
          panels: arrangePanelsInCloud(next.gridMode, basePanels),
        );
        return next;
      },
      historyEvent:
          (before, after, revision) => _gridModeHistoryEvent(
            boardId,
            'board.gridReset',
            before,
            after,
            revision,
          ),
    );
  }

  Future<void> movePanelInGrid(
    String boardId,
    String panelId, {
    required int deltaCol,
    required int deltaRow,
  }) async {
    await _updateBoard(
      boardId,
      (board) => board.copyWith(
        panels: pushPanelInGrid(
          board.gridMode,
          board.panels,
          panelId,
          deltaCol,
          deltaRow,
        ),
      ),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'panel.movedInGrid',
            entityType: 'panel',
            entityId: panelId,
            revision: revision,
            before: _panelSnapshot(
              before.panels.firstWhere((p) => p.id == panelId),
            ),
            after: _panelSnapshot(
              after.panels.firstWhere((p) => p.id == panelId),
            ),
          ),
    );
  }

  Future<void> resizePanelInGrid(
    String panelId, {
    required int deltaCols,
    required int deltaRows,
    String? boardId,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    final board = state.boards.firstWhere((b) => b.id == targetId);
    final mode = board.gridMode;
    await updatePanel(
      panelId,
      (panel) => panel.copyWith(
        bounds: resizeBoundsInGrid(
          mode,
          panel.bounds,
          deltaCols: deltaCols,
          deltaRows: deltaRows,
        ),
      ),
      boardId: targetId,
    );
  }

  /// Snaps a panel to the given grid cell and pushes overlapping neighbours.
  ///
  /// When [targetRect] is omitted the panel is snapped to the nearest cell of
  /// its current bounds. This is the commit step used after a smooth freeform
  /// drag or resize inside grid mode.
  Future<void> placePanelInGrid(
    String boardId,
    String panelId, {
    GridRect? targetRect,
    bool recordHistory = true,
  }) async {
    await _updateBoard(
      boardId,
      (board) {
        final panel = board.panels.firstWhereOrNull((p) => p.id == panelId);
        if (panel == null) return board;
        final resolvedTarget =
            targetRect ?? boundsToGridRect(board.gridMode, panel.bounds);
        return board.copyWith(
          panels: pushPanelToRect(
            board.gridMode,
            board.panels,
            panelId,
            resolvedTarget,
          ),
        );
      },
      historyEvent:
          recordHistory
              ? (before, after, revision) => _historyEvent(
                boardId: boardId,
                type: 'panel.placedInGrid',
                entityType: 'panel',
                entityId: panelId,
                revision: revision,
                before: _panelSnapshot(
                  before.panels.firstWhere((p) => p.id == panelId),
                ),
                after: _panelSnapshot(
                  after.panels.firstWhere((p) => p.id == panelId),
                ),
              )
              : null,
    );
  }


  // ── Panel groups ──────────────────────────────────────────────────────────

  static const double _collapsedCardWidth = 152;
  static const double _collapsedCardHeight = 112;
  static const double _collapsedCardOffset = 16;
  static const double _collapsedMinCardWidth = 80;
  static const double _collapsedMinCardHeight = 60;
  static const int _collapsedMaxCards = 5;

  BoardPanelBounds? _originalBounds(BoardPanelInstance panel) {
    final raw = panel.state['_originalBounds'];
    if (raw is Map<String, dynamic>) {
      return BoardPanelBounds.fromJson(raw);
    }
    return null;
  }

  Map<String, dynamic>? _groupJson(
    List<BoardPanelGroup> groups,
    String groupId,
  ) => groups.firstWhereOrNull((g) => g.id == groupId)?.toJson();

  BoardPanelInstance _restorePanelBounds(BoardPanelInstance panel) {
    final original = _originalBounds(panel);
    final nextState = Map<String, dynamic>.from(panel.state)
      ..remove('_originalBounds');
    return panel.copyWith(
      hidden: false,
      bounds: original ?? panel.bounds,
      state: nextState,
    );
  }

  BoardPanelInstance _savePanelOriginalBounds(BoardPanelInstance panel) {
    final original = _originalBounds(panel) ?? panel.bounds;
    final nextState = Map<String, dynamic>.from(panel.state)
      ..['_originalBounds'] = original.toJson();
    return panel.copyWith(state: nextState);
  }

  List<BoardPanelInstance> _layoutCollapsedPanels(
    BoardDocument board,
    BoardPanelGroup group,
    List<String> visibleIds,
    Rect stackBounds, {
    required bool saveOriginalBounds,
  }) {
    final maxZ = board.panels.fold<int>(
      0,
      (value, panel) => panel.zIndex > value ? panel.zIndex : value,
    );
    return board.panels.map((panel) {
      if (!group.panelIds.contains(panel.id)) return panel;
      final visibleIndex = visibleIds.indexOf(panel.id);
      final isVisible = visibleIndex != -1;
      final basePanel = saveOriginalBounds ? _savePanelOriginalBounds(panel) : panel;
      if (!isVisible) {
        return basePanel.copyWith(hidden: true);
      }
      final stackedBounds = _stackedCardBounds(
        stackBounds,
        visibleIndex,
        visibleIds.length,
      );
      return basePanel.copyWith(
        hidden: false,
        bounds: stackedBounds,
        zIndex: maxZ + 1 + visibleIndex,
      );
    }).toList();
  }

  Rect _groupExpandedBounds(BoardDocument board, BoardPanelGroup group) {
    Rect? union;
    for (final panelId in group.panelIds) {
      final panel = board.panels.firstWhereOrNull((p) => p.id == panelId);
      if (panel == null) continue;
      final bounds = _originalBounds(panel) ?? panel.bounds;
      final rect = Rect.fromLTWH(
        bounds.x,
        bounds.y,
        bounds.width,
        bounds.height,
      );
      union = union?.expandToInclude(rect) ?? rect;
    }
    return union ?? Rect.zero;
  }

  List<String> _orderedVisiblePanelIds(BoardPanelGroup group) {
    final focusId = group.collapsedFocusPanelId;
    final ids = List<String>.from(group.panelIds);
    if (focusId != null && ids.contains(focusId)) {
      ids.remove(focusId);
      ids.add(focusId);
    }
    if (ids.length <= _collapsedMaxCards) return ids;
    return ids.sublist(ids.length - _collapsedMaxCards);
  }

  /// Returns the container rect for a collapsed group in board coordinates.
  /// If the group already has explicit [collapsedBounds], those are used;
  /// otherwise a default size is anchored at the group's expanded bounds.
  Rect _collapsedStackBounds(
    BoardDocument board,
    BoardPanelGroup group,
    int visibleCount,
  ) {
    final saved = group.collapsedBounds;
    if (saved != null) {
      return Rect.fromLTWH(saved.x, saved.y, saved.width, saved.height);
    }
    final expanded = _groupExpandedBounds(board, group);
    final count = math.max(visibleCount, 1);
    return Rect.fromLTWH(
      expanded.left,
      expanded.top,
      _collapsedCardWidth + (count - 1) * _collapsedCardOffset,
      _collapsedCardHeight + (count - 1) * _collapsedCardOffset,
    );
  }

  BoardPanelBounds _stackedCardBounds(
    Rect stackBounds,
    int visibleIndex,
    int visibleCount,
  ) {
    final count = math.max(visibleCount, 1);
    final totalOffset = (count - 1) * _collapsedCardOffset;
    final width = math.max(
      stackBounds.width - totalOffset,
      _collapsedMinCardWidth,
    );
    final height = math.max(
      stackBounds.height - totalOffset,
      _collapsedMinCardHeight,
    );
    return BoardPanelBounds(
      x: stackBounds.left + visibleIndex * _collapsedCardOffset,
      y: stackBounds.top + visibleIndex * _collapsedCardOffset,
      width: width,
      height: height,
    );
  }

  List<BoardPanelGroup> _removePanelFromAllGroups(
    List<BoardPanelGroup> groups,
    String panelId,
  ) {
    return groups
        .map(
          (group) => group.copyWith(
            panelIds: group.panelIds.where((id) => id != panelId).toList(),
          ),
        )
        .toList();
  }

  Future<void> createGroup(
    String boardId, {
    required String name,
    List<String> panelIds = const [],
    int? color,
  }) async {
    await _updateBoard(
      boardId,
      (board) {
        var nextGroups = board.groups;
        for (final panelId in panelIds) {
          nextGroups = _removePanelFromAllGroups(nextGroups, panelId);
        }
        final group = BoardPanelGroup(
          id: _nextId('group'),
          name: name.trim().isEmpty ? 'Group' : name.trim(),
          color: color,
          panelIds: panelIds,
          collapsed: false,
        );
        return board.copyWith(groups: [...nextGroups, group]);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.created',
            entityType: 'group',
            entityId: after.groups.last.id,
            revision: revision,
            before: null,
            after: after.groups.last.toJson(),
          ),
    );
  }

  Future<void> deleteGroup(String boardId, String groupId) async {
    await _updateBoard(
      boardId,
      (board) {
        final removed = board.groups.firstWhereOrNull((g) => g.id == groupId);
        if (removed == null) return board;
        final remaining = board.groups.where((g) => g.id != groupId).toList();
        // Restore visibility and original bounds of collapsed group panels.
        var panels = board.panels;
        if (removed.collapsed) {
          panels = panels.map((panel) {
            if (removed.panelIds.contains(panel.id)) {
              return _restorePanelBounds(panel);
            }
            return panel;
          }).toList();
        }
        return board.copyWith(groups: remaining, panels: panels);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.deleted',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before:
                before.groups.firstWhereOrNull((g) => g.id == groupId)?.toJson(),
            after: null,
          ),
    );
  }

  Future<void> renameGroup(
    String boardId,
    String groupId,
    String name,
  ) async {
    await _updateBoard(
      boardId,
      (board) => board.copyWith(
        groups:
            board.groups.map((group) {
              if (group.id != groupId) return group;
              return group.copyWith(
                name: name.trim().isEmpty ? group.name : name.trim(),
              );
            }).toList(),
      ),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.renamed',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before: _groupJson(before.groups, groupId),
            after: _groupJson(after.groups, groupId),
          ),
    );
  }

  Future<void> setGroupColor(
    String boardId,
    String groupId,
    int? color,
  ) async {
    await _updateBoard(
      boardId,
      (board) => board.copyWith(
        groups:
            board.groups.map((group) {
              if (group.id != groupId) return group;
              return group.copyWith(
                color: color,
                clearColor: color == null,
              );
            }).toList(),
      ),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.colorChanged',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before: _groupJson(before.groups, groupId),
            after: _groupJson(after.groups, groupId),
          ),
    );
  }

  Future<void> addPanelsToGroup(
    String boardId,
    String groupId,
    List<String> panelIds,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        var nextGroups = board.groups;
        for (final panelId in panelIds) {
          nextGroups = _removePanelFromAllGroups(nextGroups, panelId);
        }
        nextGroups = nextGroups.map((group) {
          if (group.id != groupId) return group;
          final mergedIds = <String>[
            ...group.panelIds,
            ...panelIds.where((id) => !group.panelIds.contains(id)),
          ];
          return group.copyWith(panelIds: mergedIds);
        }).toList();
        return board.copyWith(groups: nextGroups);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.panelsAdded',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before: _groupJson(before.groups, groupId),
            after: _groupJson(after.groups, groupId),
          ),
    );
  }

  Future<void> removePanelsFromGroup(
    String boardId,
    String groupId,
    List<String> panelIds,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        final targetGroup = board.groups.firstWhereOrNull(
          (g) => g.id == groupId,
        );
        if (targetGroup == null) return board;
        final nextGroups = board.groups.map((group) {
          if (group.id != groupId) return group;
          final remaining = group.panelIds
              .where((id) => !panelIds.contains(id))
              .toList();
          return group.copyWith(panelIds: remaining);
        }).toList();
        // Restore visibility and original bounds if the group is collapsed.
        var panels = board.panels;
        if (targetGroup.collapsed) {
          panels = panels.map((panel) {
            if (panelIds.contains(panel.id)) {
              return _restorePanelBounds(panel);
            }
            return panel;
          }).toList();
        }
        return board.copyWith(groups: nextGroups, panels: panels);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.panelsRemoved',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before: _groupJson(before.groups, groupId),
            after: _groupJson(after.groups, groupId),
          ),
    );
  }

  Future<void> toggleGroupCollapse(
    String boardId,
    String groupId,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        final group = board.groups.firstWhereOrNull((g) => g.id == groupId);
        if (group == null) return board;
        final collapsed = !group.collapsed;
        final focusId =
            group.collapsedFocusPanelId ??
            (group.panelIds.isEmpty ? null : group.panelIds[0]);
        final nextGroups = board.groups.map((g) {
          if (g.id != groupId) return g;
          return g.copyWith(
            collapsed: collapsed,
            collapsedFocusPanelId: collapsed ? focusId : null,
            clearCollapsedFocus: !collapsed,
          );
        }).toList();

        if (!collapsed) {
          // Expand: restore original bounds and visibility.
          final nextPanels = board.panels.map((panel) {
            if (!group.panelIds.contains(panel.id)) return panel;
            return _restorePanelBounds(panel);
          }).toList();
          return board.copyWith(groups: nextGroups, panels: nextPanels);
        }

        // Collapse: save original bounds, then stack panels inside the group's
        // collapsed bounds (explicit or default).
        final visibleIds = _orderedVisiblePanelIds(
          group.copyWith(collapsedFocusPanelId: focusId),
        );
        final stackBounds = _collapsedStackBounds(
          board,
          group,
          visibleIds.length,
        );
        final nextGroupsWithBounds = nextGroups.map((g) {
          if (g.id != groupId) return g;
          return g.collapsedBounds == null
              ? g.copyWith(
                collapsedBounds: BoardPanelBounds(
                  x: stackBounds.left,
                  y: stackBounds.top,
                  width: stackBounds.width,
                  height: stackBounds.height,
                ),
              )
              : g;
        }).toList();
        final nextPanels = _layoutCollapsedPanels(
          board,
          group,
          visibleIds,
          stackBounds,
          saveOriginalBounds: true,
        );
        final focusedId = board.viewport.focusedPanelId;
        final clearFocus =
            focusedId != null && group.panelIds.contains(focusedId);
        return board.copyWith(
          groups: nextGroupsWithBounds,
          panels: nextPanels,
          viewport:
              clearFocus
                  ? board.viewport.copyWith(clearFocusedPanelId: true)
                  : null,
        );
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: boardId,
            type: 'group.toggledCollapse',
            entityType: 'group',
            entityId: groupId,
            revision: revision,
            before: _groupJson(before.groups, groupId),
            after: _groupJson(after.groups, groupId),
          ),
    );
  }

  /// Moves every panel in [groupId] by [delta].
  Future<void> moveGroup(
    String boardId,
    String groupId,
    Offset delta,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        final group = board.groups.firstWhereOrNull((g) => g.id == groupId);
        if (group == null || delta == Offset.zero) return board;
        final nextPanels = board.panels.map((panel) {
          if (!group.panelIds.contains(panel.id)) return panel;
          final original = _originalBounds(panel);
          final movedBounds = panel.bounds.copyWith(
            x: panel.bounds.x + delta.dx,
            y: panel.bounds.y + delta.dy,
          );
          final nextState = Map<String, dynamic>.from(panel.state);
          if (original != null) {
            nextState['_originalBounds'] = original
                .copyWith(
                  x: original.x + delta.dx,
                  y: original.y + delta.dy,
                )
                .toJson();
          }
          return panel.copyWith(bounds: movedBounds, state: nextState);
        }).toList();
        final nextGroups = board.groups.map((g) {
          if (g.id != groupId) return g;
          final bounds = g.collapsedBounds;
          if (bounds == null) return g;
          return g.copyWith(
            collapsedBounds: bounds.copyWith(
              x: bounds.x + delta.dx,
              y: bounds.y + delta.dy,
            ),
          );
        }).toList();
        return board.copyWith(panels: nextPanels, groups: nextGroups);
      },
      historyEvent: null,
    );
  }

  /// Resizes a collapsed group's container to [newBounds] and reflows the
  /// stacked panel cards so they fill the new size.
  Future<void> resizeGroupCollapsedBounds(
    String boardId,
    String groupId,
    BoardPanelBounds newBounds,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        final group = board.groups.firstWhereOrNull((g) => g.id == groupId);
        if (group == null || !group.collapsed) return board;
        final stackBounds = Rect.fromLTWH(
          newBounds.x,
          newBounds.y,
          newBounds.width,
          newBounds.height,
        );
        final visibleIds = _orderedVisiblePanelIds(group);
        final nextPanels = _layoutCollapsedPanels(
          board,
          group,
          visibleIds,
          stackBounds,
          saveOriginalBounds: false,
        );
        final nextGroups = board.groups.map((g) {
          if (g.id != groupId) return g;
          return g.copyWith(collapsedBounds: newBounds);
        }).toList();
        return board.copyWith(groups: nextGroups, panels: nextPanels);
      },
      historyEvent: null,
    );
  }

  /// Cycles the focused panel inside a collapsed group.
  ///
  /// [direction] 1 for next, -1 for previous.
  Future<void> cycleGroupFocus(
    String boardId,
    String groupId,
    int direction,
  ) async {
    await _updateBoard(
      boardId,
      (board) {
        final group = board.groups.firstWhereOrNull((g) => g.id == groupId);
        if (group == null || group.panelIds.isEmpty || !group.collapsed) {
          return board;
        }
        final panelIds = group.panelIds;
        final currentId = group.collapsedFocusPanelId;
        var index = 0;
        if (currentId != null) {
          final found = panelIds.indexOf(currentId);
          if (found != -1) index = found;
        }
        final nextIndex = (index + direction) % panelIds.length;
        final focusedId = panelIds[nextIndex];
        final nextGroup = group.copyWith(collapsedFocusPanelId: focusedId);
        final visibleIds = _orderedVisiblePanelIds(nextGroup);
        final stackBounds = _collapsedStackBounds(
          board,
          nextGroup,
          visibleIds.length,
        );
        final nextPanels = _layoutCollapsedPanels(
          board,
          group,
          visibleIds,
          stackBounds,
          saveOriginalBounds: false,
        );
        final nextGroups = board.groups.map((g) {
          if (g.id != groupId) return g;
          return nextGroup;
        }).toList();
        return board.copyWith(groups: nextGroups, panels: nextPanels);
      },
      historyEvent: null,
    );
  }

  // ── Multi-selection ───────────────────────────────────────────────────────

  void selectPanels(Set<String> panelIds) {
    emit(state.copyWith(selectedPanelIds: panelIds));
  }

  void togglePanelSelection(String panelId) {
    final current = state.selectedPanelIds;
    if (current.contains(panelId)) {
      emit(state.copyWith(selectedPanelIds: current.difference({panelId})));
    } else {
      emit(state.copyWith(selectedPanelIds: current.union({panelId})));
    }
  }

  void clearSelection() {
    emit(state.copyWith(clearSelection: true));
  }

  void selectPanelsInRect(Rect rect) {
    final board = state.activeBoard;
    if (board == null) return;
    final ids = <String>{};
    for (final panel in board.panels) {
      if (panel.hidden) continue;
      final panelRect = Rect.fromLTWH(
        panel.bounds.x,
        panel.bounds.y,
        panel.bounds.width,
        panel.bounds.height,
      );
      if (rect.overlaps(panelRect)) {
        ids.add(panel.id);
      }
    }
    emit(state.copyWith(selectedPanelIds: ids));
  }

  Future<void> createGroupFromSelection({
    required String name,
    int? color,
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final panelIds = state.selectedPanelIds.toList();
    if (panelIds.isEmpty) return;
    await createGroup(
      board.id,
      name: name,
      panelIds: panelIds,
      color: color,
    );
    emit(state.copyWith(clearSelection: true));
  }

  Future<void> createMarkdownNote({
    required String title,
    required String markdown,
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final bounds = _nextAvailableBounds(
      board,
      preferredWidth: 320,
      preferredHeight: 220,
    );
    final panel = BoardPanelInstance(
      id: _nextId('panel'),
      type: 'board.note.markdown',
      title: title.trim().isEmpty ? 'Note' : title.trim(),
      bounds: bounds,
      state: {'markdown': markdown},
      zIndex:
          board.panels.fold<int>(
            0,
            (value, panel) => panel.zIndex > value ? panel.zIndex : value,
          ) +
          1,
    );
    await addPanel(panel);
    await focusPanel(panel.id);
  }

  Future<void> createChatPanel({
    String? title,
    String? sessionName,
    String workingDir = '',
    String model = 'gpt-5-mini',
    String? provider,
    List<String> envGroupIds = const [],
    List<Map<String, dynamic>>? messages,
    bool? configured,
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final bounds = _nextAvailableBounds(
      board,
      preferredWidth: 420,
      preferredHeight: 500,
    );

    final effectiveProvider =
        provider ?? AgentConfigService.instance.defaultAgentId ?? 'copilot';

    // Resolve effective model: user's explicit arg → agent default model → catalog default → hardcoded default
    final effectiveModel = _resolveDefaultModel(effectiveProvider, model);
    final effectiveWorkingDir = _effectiveBoardFolder(board, workingDir);

    final config = ChatSessionConfig(
      sessionName:
          sessionName ?? 'chat-${DateTime.now().millisecondsSinceEpoch}',
      workingDir: effectiveWorkingDir,
      model: effectiveModel,
      provider: effectiveProvider,
      envGroupIds: envGroupIds,
    );
    final panelState = <String, dynamic>{
      'config': config.toJson(),
      'configured':
          configured ??
          (messages != null && messages.isNotEmpty) ||
              effectiveWorkingDir.trim().isNotEmpty,
    };
    if (messages != null && messages.isNotEmpty) {
      panelState['messages'] = messages;
    }
    final panel = BoardPanelInstance(
      id: _nextId('panel'),
      type: kChatPluginTypeId,
      title: title?.trim().isNotEmpty == true ? title!.trim() : 'AI Chat',
      bounds: bounds,
      state: panelState,
      zIndex:
          board.panels.fold<int>(
            0,
            (value, panel) => panel.zIndex > value ? panel.zIndex : value,
          ) +
          1,
    );
    await addPanel(panel);
    await focusPanel(panel.id);
  }

  Future<void> createTerminalPanel({
    String? title,
    String? sessionId,
    String? sessionName,
    String workingDir = '',
    List<String> envGroupIds = const [],
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final bounds = _nextAvailableBounds(
      board,
      preferredWidth: 520,
      preferredHeight: 360,
    );
    final effectiveWorkingDir = _effectiveBoardFolder(board, workingDir);
    final config = BoardTerminalConfig(
      sessionId: sessionId ?? '',
      sessionName: sessionName ?? '',
      workingDir: effectiveWorkingDir,
      envGroupIds: envGroupIds,
    );
    final panel = BoardPanelInstance(
      id: _nextId('panel'),
      type: kTerminalPluginTypeId,
      title:
          title?.trim().isNotEmpty == true
              ? title!.trim()
              : (sessionName?.trim().isNotEmpty == true
                  ? sessionName!.trim()
                  : 'Terminal'),
      bounds: bounds,
      state: {'config': config.toJson()},
      zIndex:
          board.panels.fold<int>(
            0,
            (value, panel) => panel.zIndex > value ? panel.zIndex : value,
          ) +
          1,
    );
    await addPanel(panel);
    await focusPanel(panel.id);
  }

  /// Creates a panel for any registered plugin type using its default size and
  /// initial state. Use for generic plugins (kanban, checklist, etc.).
  Future<void> createGenericPanel(
    String typeId, {
    String? title,
    Map<String, dynamic> panelState = const {},
    Size? preferredSize,
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
    if (plugin == null) return;
    final size = preferredSize ?? plugin.defaultSize;
    final initialState = <String, dynamic>{
      ..._initialStateForBoard(plugin.initialState, typeId, board),
      ...panelState,
    };
    final bounds = _nextAvailableBounds(
      board,
      preferredWidth: size.width,
      preferredHeight: size.height,
    );
    final panel = BoardPanelInstance(
      id: _nextId('panel'),
      type: typeId,
      title:
          title?.trim().isNotEmpty == true ? title!.trim() : plugin.displayName,
      bounds: bounds,
      state: initialState,
      zIndex:
          board.panels.fold<int>(
            0,
            (value, p) => p.zIndex > value ? p.zIndex : value,
          ) +
          1,
    );
    await addPanel(panel);
    await focusPanel(panel.id);
  }

  Future<void> addPanel(BoardPanelInstance panel, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) => board.copyWith(panels: [...board.panels, panel]),
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: targetId,
            type: 'panel.created',
            entityType: 'panel',
            entityId: panel.id,
            revision: revision,
            after: _panelSnapshot(panel),
          ),
    );
  }

  Future<void> updatePanel(
    String panelId,
    BoardPanelInstance Function(BoardPanelInstance panel) update, {
    String? boardId,
    bool recordHistory = true,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updatedPanels =
            board.panels
                .map((panel) => panel.id == panelId ? update(panel) : panel)
                .toList();
        return board.copyWith(panels: updatedPanels);
      },
      historyEvent:
          recordHistory
              ? (before, after, revision) {
                final beforePanel = before.panels.firstWhereOrNull(
                  (panel) => panel.id == panelId,
                );
                final afterPanel = after.panels.firstWhereOrNull(
                  (panel) => panel.id == panelId,
                );
                if (beforePanel == null ||
                    afterPanel == null ||
                    beforePanel == afterPanel) {
                  return null;
                }
                return _historyEvent(
                  boardId: targetId,
                  type: 'panel.updated',
                  entityType: 'panel',
                  entityId: panelId,
                  revision: revision,
                  before: _panelSnapshot(beforePanel),
                  after: _panelSnapshot(afterPanel),
                  patch: _panelPatch(beforePanel, afterPanel),
                );
              }
              : null,
    );
  }

  /// Copies [panelIds] (or the current selection) to the system clipboard as a
  /// JSON payload. Returns the copied panel ids.
  Future<List<String>> copyPanels([Set<String>? panelIds]) async {
    final board = state.activeBoard;
    if (board == null) return const [];
    final ids = panelIds ?? state.selectedPanelIds;
    if (ids.isEmpty) return const [];
    final panels = board.panels.where((p) => ids.contains(p.id)).toList();
    if (panels.isEmpty) return const [];
    final linkIds = ids;
    final links = board.links
        .where((l) => linkIds.contains(l.fromPanelId) && linkIds.contains(l.toPanelId))
        .toList();
    final payload = jsonEncode({
      'version': 1,
      'kind': 'yoloit/panels',
      'panels': panels.map((p) => p.toJson()).toList(),
      'links': links.map((l) => l.toJson()).toList(),
    });
    await _clipboard.setText(payload);
    return panels.map((p) => p.id).toList();
  }

  /// Pastes panels from the system clipboard onto the active board. Returns the
  /// ids of the newly created panels.
  Future<List<String>> pastePanels({Offset offset = const Offset(40, 40)}) async {
    final board = state.activeBoard;
    if (board == null) return const [];
    final text = await _clipboard.getText();
    if (text == null || text.isEmpty) return const [];
    Map<String, dynamic> payload;
    try {
      payload = jsonDecode(text) as Map<String, dynamic>;
    } on FormatException {
      return const [];
    }
    if (payload['kind'] != 'yoloit/panels') return const [];
    final rawPanels = payload['panels'] as List<dynamic>? ?? const [];
    final rawLinks = payload['links'] as List<dynamic>? ?? const [];
    if (rawPanels.isEmpty) return const [];

    final idMap = <String, String>{};
    var maxZ = board.panels.fold<int>(
      0,
      (value, panel) => panel.zIndex > value ? panel.zIndex : value,
    );

    final copiedPanels = rawPanels.map((raw) {
      final json = Map<String, dynamic>.from(raw as Map);
      final oldId = json['id'] as String;
      final newId = _nextId('panel');
      idMap[oldId] = newId;
      final bounds = BoardPanelBounds.fromJson(
        Map<String, dynamic>.from(json['bounds'] as Map),
      );
      final newBounds = bounds.copyWith(
        x: bounds.x + offset.dx,
        y: bounds.y + offset.dy,
      );
      maxZ++;
      return BoardPanelInstance.fromJson({
        ...json,
        'id': newId,
        'bounds': newBounds.toJson(),
        'zIndex': maxZ,
      });
    }).toList();

    final copiedLinks = rawLinks.map((raw) {
      final json = Map<String, dynamic>.from(raw as Map);
      final newFrom = idMap[json['fromPanelId'] as String];
      final newTo = idMap[json['toPanelId'] as String];
      if (newFrom == null || newTo == null) return null;
      return BoardPanelLink.fromJson({
        ...json,
        'id': _nextId('link'),
        'fromPanelId': newFrom,
        'toPanelId': newTo,
      });
    }).whereType<BoardPanelLink>().toList();

    await _updateBoard(
      board.id,
      (b) => b.copyWith(
        panels: [...b.panels, ...copiedPanels],
        links: [...b.links, ...copiedLinks],
      ),
      historyEvent: (before, after, revision) => _historyEvent(
        boardId: board.id,
        type: 'panel.created',
        entityType: 'panel',
        entityId: copiedPanels.map((p) => p.id).join(','),
        revision: revision,
        after: <String, dynamic>{
          'panels': copiedPanels.map(_panelSnapshot).toList(),
        },
      ),
    );
    await _copyCalendarEvents(copiedPanels, idMap);
    emit(state.copyWith(selectedPanelIds: copiedPanels.map((p) => p.id).toSet()));
    return copiedPanels.map((p) => p.id).toList();
  }

  /// Duplicates [panelIds] (or the current selection) in place.
  Future<List<String>> duplicatePanels([Set<String>? panelIds]) async {
    final ids = panelIds ?? state.selectedPanelIds;
    if (ids.isEmpty) return const [];
    final copied = await copyPanels(ids);
    if (copied.isEmpty) return const [];
    final pasted = await pastePanels();
    return pasted;
  }

  Future<void> _copyCalendarEvents(
    List<BoardPanelInstance> pastedPanels,
    Map<String, String> idMap,
  ) async {
    const storage = CalendarEventStorage();
    for (final panel in pastedPanels.where((p) => p.type == 'board.calendar')) {
      final oldId = idMap.entries.firstWhere((e) => e.value == panel.id).key;
      await storage.copyEvents(oldId, panel.id);
    }
  }

  Future<void> movePanel(
    String panelId,
    Offset delta, {
    String? boardId,
    bool recordHistory = true,
  }) async {
    await updatePanel(
      panelId,
      (panel) => panel.copyWith(
        bounds: panel.bounds.copyWith(
          x: panel.bounds.x + delta.dx,
          y: panel.bounds.y + delta.dy,
        ),
      ),
      boardId: boardId,
      recordHistory: recordHistory,
    );
  }

  Future<void> resizePanel(
    String panelId, {
    required double width,
    required double height,
    double minWidth = 220,
    double minHeight = 140,
    String? boardId,
  }) async {
    await updatePanel(
      panelId,
      (panel) => panel.copyWith(
        bounds: panel.bounds.copyWith(
          width: width < minWidth ? minWidth : width,
          height: height < minHeight ? minHeight : height,
        ),
      ),
      boardId: boardId,
    );
  }

  Future<void> updateMarkdownNote(
    String panelId, {
    required String title,
    required String markdown,
    String? boardId,
  }) async {
    await updatePanel(
      panelId,
      (panel) => panel.copyWith(
        title: title.trim().isEmpty ? panel.title : title.trim(),
        state: {...panel.state, 'markdown': markdown},
      ),
      boardId: boardId,
    );
  }

  Future<void> updatePanelColor(
    String panelId, {
    required Color? color,
    String? boardId,
  }) async {
    await updatePanel(
      panelId,
      (panel) =>
          color == null
              ? panel.copyWith(clearColor: true)
              : panel.copyWith(color: color),
      boardId: boardId,
    );
  }

  Future<void> updatePanelTitle(
    String panelId,
    String title, {
    String? boardId,
  }) async {
    await updatePanel(
      panelId,
      (panel) => panel.copyWith(title: title),
      boardId: boardId,
    );
  }

  Future<void> removePanel(
    String panelId, {
    String? boardId,
    bool recordHistory = true,
  }) async {
    if (state.yoloAssistantAnchorPanelId == panelId) {
      closeYoloAssistant();
    }
    // Release any persistent resources tied to the panel (e.g. media player).
    PlaylistPlayerRegistry.instance.release(panelId);
    WebViewManager.instance.remove(panelId);
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updatedPanels =
            board.panels.where((panel) => panel.id != panelId).toList();
        final updatedLinks =
            board.links
                .where(
                  (link) =>
                      link.fromPanelId != panelId && link.toPanelId != panelId,
                )
                .toList();
        final clearFocused = board.viewport.focusedPanelId == panelId;
        return board.copyWith(
          panels: updatedPanels,
          links: updatedLinks,
          viewport:
              clearFocused
                  ? board.viewport.copyWith(clearFocusedPanelId: true)
                  : board.viewport,
        );
      },
      historyEvent:
          recordHistory
              ? (before, after, revision) {
                final removedPanel = before.panels.firstWhereOrNull(
                  (panel) => panel.id == panelId,
                );
                if (removedPanel == null) return null;
                final removedLinks =
                    before.links
                        .where(
                          (link) =>
                              link.fromPanelId == panelId ||
                              link.toPanelId == panelId,
                        )
                        .map((link) => link.toJson())
                        .toList();
                return _historyEvent(
                  boardId: targetId,
                  type: 'panel.deleted',
                  entityType: 'panel',
                  entityId: panelId,
                  revision: revision,
                  before: _panelSnapshot(removedPanel),
                  patch: {'removedLinks': removedLinks},
                );
              }
              : null,
    );
  }

  Future<void> upsertLink(BoardPanelLink link, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updated = [
          ...board.links.where((entry) => entry.id != link.id),
          link,
        ];
        return board.copyWith(links: updated);
      },
      historyEvent: (before, after, revision) {
        final beforeLink = before.links.firstWhereOrNull(
          (entry) => entry.id == link.id,
        );
        return _historyEvent(
          boardId: targetId,
          type: beforeLink == null ? 'link.created' : 'link.updated',
          entityType: 'link',
          entityId: link.id,
          revision: revision,
          before: beforeLink?.toJson(),
          after: link.toJson(),
        );
      },
    );
  }

  Future<void> removeLink(String linkId, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updated = board.links.where((link) => link.id != linkId).toList();
        return board.copyWith(links: updated);
      },
      historyEvent: (before, after, revision) {
        final removedLink = before.links.firstWhereOrNull(
          (link) => link.id == linkId,
        );
        if (removedLink == null) return null;
        return _historyEvent(
          boardId: targetId,
          type: 'link.deleted',
          entityType: 'link',
          entityId: linkId,
          revision: revision,
          before: removedLink.toJson(),
        );
      },
    );
  }

  // ── Drawing elements ──────────────────────────────────────────────────────

  Future<void> addDrawing(
    BoardDrawingElement drawing, {
    String? boardId,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        return board.copyWith(drawings: [...board.drawings, drawing]);
      },
      historyEvent:
          (before, after, revision) => _historyEvent(
            boardId: targetId,
            type: 'drawing.created',
            entityType: 'drawing',
            entityId: drawing.id,
            revision: revision,
            after: drawing.toJson(),
          ),
    );
  }

  Future<void> moveDrawing(
    String drawingId,
    Offset position, {
    String? boardId,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updated =
            board.drawings.map((d) {
              return d.id == drawingId ? d.copyWith(position: position) : d;
            }).toList();
        return board.copyWith(drawings: updated);
      },
      historyEvent: (before, after, revision) {
        final beforeDrawing = before.drawings.firstWhereOrNull(
          (drawing) => drawing.id == drawingId,
        );
        final afterDrawing = after.drawings.firstWhereOrNull(
          (drawing) => drawing.id == drawingId,
        );
        if (beforeDrawing == null ||
            afterDrawing == null ||
            beforeDrawing == afterDrawing) {
          return null;
        }
        return _historyEvent(
          boardId: targetId,
          type: 'drawing.updated',
          entityType: 'drawing',
          entityId: drawingId,
          revision: revision,
          before: beforeDrawing.toJson(),
          after: afterDrawing.toJson(),
        );
      },
    );
  }

  Future<void> removeDrawing(String drawingId, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) {
        final updated = board.drawings.where((d) => d.id != drawingId).toList();
        return board.copyWith(drawings: updated);
      },
      historyEvent: (before, after, revision) {
        final removedDrawing = before.drawings.firstWhereOrNull(
          (drawing) => drawing.id == drawingId,
        );
        if (removedDrawing == null) return null;
        return _historyEvent(
          boardId: targetId,
          type: 'drawing.deleted',
          entityType: 'drawing',
          entityId: drawingId,
          revision: revision,
          before: removedDrawing.toJson(),
        );
      },
    );
  }

  Future<void> _updateBoard(
    String boardId,
    BoardDocument Function(BoardDocument board) update, {
    BoardHistoryEvent? Function(
      BoardDocument before,
      BoardDocument after,
      int revision,
    )?
    historyEvent,
  }) async {
    final boards = state.boards;
    final index = boards.indexWhere((board) => board.id == boardId);
    if (index == -1) return;
    final updatedBoards = [...boards];
    final beforeBoard = updatedBoards[index];
    final updatedBoard = update(beforeBoard);
    BoardHistoryEvent? event;
    var afterBoard = updatedBoard;
    if (historyEvent != null && updatedBoard != beforeBoard) {
      final revision = _historyRevision(beforeBoard) + 1;
      afterBoard = _withHistoryRevision(updatedBoard, revision);
      event = historyEvent(beforeBoard, afterBoard, revision);
    }
    updatedBoards[index] = afterBoard;
    await _setBoards(
      updatedBoards,
      activeBoardId: state.activeBoardId ?? boardId,
    );
    if (event != null) {
      await _appendHistory(event);
    }
  }

  BoardHistoryEvent _historyEvent({
    required String boardId,
    required String type,
    required String entityType,
    required String entityId,
    required int revision,
    Map<String, dynamic>? before,
    Map<String, dynamic>? after,
    Map<String, dynamic> patch = const {},
    String? restoresOpId,
  }) {
    return BoardHistoryEvent(
      opId: _nextId('op'),
      boardId: boardId,
      type: type,
      entityType: entityType,
      entityId: entityId,
      actorId: _actorId,
      timestamp: DateTime.now().toUtc(),
      revision: revision,
      before: before,
      after: after,
      patch: patch,
      restoresOpId: restoresOpId,
    );
  }

  Future<void> _appendHistory(BoardHistoryEvent event) async {
    if (!_replayingHistory) {
      _redoStacks.remove(event.boardId);
    }
    try {
      await _historyStore.append(event);
    } catch (error, stackTrace) {
      assert(() {
        debugPrint('[BoardCubit] failed to append board history: $error');
        return true;
      }());
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _appendPanelUpdateHistory({
    required String boardId,
    required BoardPanelInstance beforePanel,
    required BoardPanelInstance afterPanel,
  }) async {
    if (beforePanel == afterPanel) return;
    final boards = [...state.boards];
    final index = boards.indexWhere((board) => board.id == boardId);
    if (index == -1) return;
    final board = boards[index];
    final revision = _historyRevision(board) + 1;
    boards[index] = _withHistoryRevision(board, revision);
    await _setBoards(
      boards,
      activeBoardId: state.activeBoardId ?? boardId,
    );
    await _appendHistory(
      _historyEvent(
        boardId: boardId,
        type: 'panel.updated',
        entityType: 'panel',
        entityId: afterPanel.id,
        revision: revision,
        before: _panelSnapshot(beforePanel),
        after: _panelSnapshot(afterPanel),
        patch: _panelPatch(beforePanel, afterPanel),
      ),
    );
  }

  int _historyRevision(BoardDocument board) {
    return (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
  }

  BoardDocument _withHistoryRevision(BoardDocument board, int revision) {
    return board.copyWith(
      metadata: {...board.metadata, 'historyRevision': revision},
    );
  }


  void _emitPanelLockConflict(String panelId, String? actorId) {
    emit(
      state.copyWith(
        panelLockConflictPanelId: panelId,
        panelLockConflictActorId: actorId,
      ),
    );
  }

  void clearPanelLockConflict() {
    emit(state.copyWith(clearPanelLockConflict: true));
  }

  Map<String, dynamic> _panelSnapshot(BoardPanelInstance panel) {
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    final snapshot = Map<String, dynamic>.from(panel.toJson());
    snapshot['state'] =
        plugin?.historyAdapter.snapshotState(
          Map<String, dynamic>.from(panel.state),
        ) ??
        Map<String, dynamic>.from(panel.state);
    return snapshot;
  }

  BoardPanelInstance _panelFromHistorySnapshot(Map<String, dynamic> snapshot) {
    final panel = BoardPanelInstance.fromJson(snapshot);
    final plugin = BoardPluginRegistry.instance.pluginFor(panel.type);
    return panel.copyWith(
      state:
          plugin?.historyAdapter.restoreState(
            Map<String, dynamic>.from(panel.state),
          ) ??
          panel.state,
    );
  }

  Map<String, dynamic> _panelPatch(
    BoardPanelInstance before,
    BoardPanelInstance after,
  ) {
    final plugin = BoardPluginRegistry.instance.pluginFor(after.type);
    final patch = <String, dynamic>{};
    void addIfChanged(String key, Object? beforeValue, Object? afterValue) {
      if (beforeValue != afterValue) {
        patch[key] = {'before': beforeValue, 'after': afterValue};
      }
    }

    addIfChanged('title', before.title, after.title);
    addIfChanged('bounds', before.bounds.toJson(), after.bounds.toJson());
    addIfChanged('color', before.color?.toARGB32(), after.color?.toARGB32());
    addIfChanged('params', before.params, after.params);
    addIfChanged('zIndex', before.zIndex, after.zIndex);
    addIfChanged('hidden', before.hidden, after.hidden);
    addIfChanged('locked', before.locked, after.locked);
    addIfChanged('pinned', before.pinned, after.pinned);
    if (before.state != after.state) {
      patch['state'] =
          plugin?.historyAdapter.diffState(
            before: Map<String, dynamic>.from(before.state),
            after: Map<String, dynamic>.from(after.state),
          ) ??
          {'before': before.state, 'after': after.state};
    }
    return patch;
  }

  Future<void> _setBoards(
    List<BoardDocument> boards, {
    required String? activeBoardId,
  }) async {
    final previousBoards = state.boards;
    emit(
      state.copyWith(
        boards: boards,
        activeBoardId: activeBoardId,
        isLoaded: true,
      ),
    );
    await _persist(boards: boards, activeBoardId: activeBoardId);
    if (!_suppressRemoteSync) {
      final changedRemoteBoards = _changedRemoteBoards(
        previousBoards: previousBoards,
        nextBoards: boards,
      );
      if (changedRemoteBoards.isNotEmpty) {
        _scheduleRemoteSync(
          changedRemoteBoards,
          currentBoards: boards,
          activeBoardId: activeBoardId,
        );
      }
    }
    _startRemoteRefreshTimer();
  }

  List<BoardDocument> _changedRemoteBoards({
    required List<BoardDocument> previousBoards,
    required List<BoardDocument> nextBoards,
  }) {
    final previousById = {for (final board in previousBoards) board.id: board};
    return nextBoards
        .where((board) {
          if (remoteInfoForBoard(board) == null) return false;
          final previous = previousById[board.id];
          if (previous == null) return false;
          return jsonEncode(boardToRemoteJson(previous)) !=
              jsonEncode(boardToRemoteJson(board));
        })
        .toList(growable: false);
  }

  void _scheduleRemoteSync(
    List<BoardDocument> boards, {
    required List<BoardDocument> currentBoards,
    required String? activeBoardId,
  }) {
    _pendingRemoteSyncBoards = boards;
    _pendingRemoteSyncCurrentBoards = currentBoards;
    _pendingRemoteSyncActiveBoardId = activeBoardId;
    _remoteSyncDebounce?.cancel();
    _remoteSyncDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(flushRemoteSync());
    });
  }

  Future<void> flushRemoteSync() async {
    _remoteSyncDebounce?.cancel();
    _remoteSyncDebounce = null;
    if (_remoteSyncInFlight) return;
    final boards = _pendingRemoteSyncBoards;
    final currentBoards = _pendingRemoteSyncCurrentBoards;
    final activeBoardId = _pendingRemoteSyncActiveBoardId;
    if (boards == null || boards.isEmpty || currentBoards == null) return;

    _pendingRemoteSyncBoards = null;
    _pendingRemoteSyncCurrentBoards = null;
    _pendingRemoteSyncActiveBoardId = null;
    _remoteSyncInFlight = true;
    try {
      await _syncRemoteBoards(
        boards,
        currentBoards: currentBoards,
        activeBoardId: activeBoardId,
      );
    } finally {
      _remoteSyncInFlight = false;
    }
    if (_pendingRemoteSyncBoards != null) {
      await flushRemoteSync();
    }
  }

  Future<void> _syncRemoteBoards(
    List<BoardDocument> boards, {
    required List<BoardDocument> currentBoards,
    required String? activeBoardId,
  }) async {
    final replacements = <String, BoardDocument>{};
    for (final board in boards) {
      final remote = remoteInfoForBoard(board);
      if (remote == null) continue;
      try {
        final synced = await YoloitRemoteClient(
          baseUrl: remote.url,
          token: remote.token,
        ).putBoard(board);
        replacements[board.id] = synced;
      } catch (error) {
        if (error is YoloitRemoteException && error.statusCode == 409) {
          replacements[board.id] = await YoloitRemoteClient(
            baseUrl: remote.url,
            token: remote.token,
          ).fetchBoard(remote.boardId, viewportOverride: board.viewport);
          assert(() {
            debugPrint(
              '[BoardCubit] refreshed stale remote board ${board.id} after revision conflict',
            );
            return true;
          }());
          continue;
        }
        assert(() {
          debugPrint(
            '[BoardCubit] failed to sync remote board ${board.id}: $error',
          );
          return true;
        }());
      }
    }
    if (replacements.isEmpty) return;
    final nextBoards = currentBoards
        .map((board) => replacements[board.id] ?? board)
        .toList(growable: false);
    _suppressRemoteSync = true;
    try {
      await _setBoards(nextBoards, activeBoardId: activeBoardId);
    } finally {
      _suppressRemoteSync = false;
    }
  }

  Future<void> _persist({
    required List<BoardDocument> boards,
    required String? activeBoardId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _boardsStorageKey,
      jsonEncode(boards.map((board) => board.toJson()).toList()),
    );
    if (activeBoardId == null) {
      await prefs.remove(_activeBoardStorageKey);
    } else {
      await prefs.setString(_activeBoardStorageKey, activeBoardId);
    }
  }

  @override
  Future<void> close() async {
    await flushRemoteSync();
    _remoteSyncDebounce?.cancel();
    _remoteRefreshDebounce?.cancel();
    _remoteRefreshTimer?.cancel();
    _panelLockRenewalTimer?.cancel();
    await _boardEventSub?.cancel();
    return super.close();
  }

  BoardDocument _buildDefaultBoard({required String name}) {
    return BoardDocument(
      id: _nextId('board'),
      name: name,
      metadata: const {'version': 1},
    );
  }

  String _effectiveBoardFolder(BoardDocument board, String explicitFolder) {
    final explicit = explicitFolder.trim();
    if (explicit.isNotEmpty) return explicit;
    return board.defaultFolder;
  }

  Map<String, dynamic> _initialStateForBoard(
    Map<String, dynamic> initialState,
    String typeId,
    BoardDocument board,
  ) {
    return initialPanelStateForBoard(initialState, typeId, board);
  }

  /// Resolves the effective model for a new chat session.
  /// Priority: explicit non-default arg → agent defaultModel setting → catalog default → hardcoded fallback.
  String _resolveDefaultModel(String provider, String explicitModel) {
    const hardcodedDefault = 'gpt-5-mini';
    // If caller passed something other than the hardcoded default, use it as-is.
    if (explicitModel != hardcodedDefault) return explicitModel;
    // Check agent config for user-set default model.
    final agentDefault = AgentConfigService.instance.defaultModelForAgent(
      provider,
    );
    if (agentDefault != null && agentDefault.isNotEmpty) return agentDefault;
    // Fall back to the first isDefault model in the catalog.
    final catalogDefault = ProviderModelCatalogService.instance
        .defaultModelForProvider(provider);
    if (catalogDefault != null) return catalogDefault;
    return hardcodedDefault;
  }

  String _nextBoardName(String? requestedName) {
    final trimmed = requestedName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    final existing = state.boards.map((board) => board.name).toSet();
    var index = 1;
    while (existing.contains('Board $index')) {
      index++;
    }
    return 'Board $index';
  }

  String _nextId(String prefix) =>
      '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  /// Public API for external widgets (e.g. [BoardPanelLayer]) that need to
  /// place a new panel without duplicating the search logic.
  BoardPanelBounds nextAvailableBounds(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  }) => _nextAvailableBounds(
    board,
    preferredWidth: preferredWidth,
    preferredHeight: preferredHeight,
  );

  BoardPanelBounds _nextAvailableBounds(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  }) {
    if (board.gridMode.enabled) {
      return _nextAvailableGridBounds(
        board,
        preferredWidth: preferredWidth,
        preferredHeight: preferredHeight,
      );
    }

    return nextAvailableFreeformBounds(
      board,
      preferredWidth: preferredWidth,
      preferredHeight: preferredHeight,
    );
  }

  BoardPanelBounds _nextAvailableGridBounds(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  }) {
    final mode = board.gridMode;
    final rects = buildGridRects(
      mode,
      board.panels.where((p) => !p.hidden).toList(),
    );
    final probe = BoardPanelBounds(
      x: 0,
      y: 0,
      width: preferredWidth,
      height: preferredHeight,
    );
    final probeRect = boundsToGridRect(mode, probe);

    // Search a generous region around the origin for the first free slot.
    const searchRadius = 12;
    for (var row = 0; row < searchRadius; row++) {
      for (var col = 0; col < searchRadius; col++) {
        final candidate = GridRect(
          col,
          row,
          colSpan: probeRect.colSpan,
          rowSpan: probeRect.rowSpan,
        );
        final overlaps = rects.values.any(candidate.overlaps);
        if (!overlaps) {
          return gridRectToBounds(mode, candidate);
        }
      }
    }

    // Fallback: place below the occupied region.
    final maxRow =
        rects.values.isEmpty
            ? 0
            : rects.values.map((r) => r.bottom).reduce(math.max);
    return gridRectToBounds(
      mode,
      GridRect(
        0,
        maxRow + 1,
        colSpan: probeRect.colSpan,
        rowSpan: probeRect.rowSpan,
      ),
    );
  }
}

extension _BoardCubitIterable<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
