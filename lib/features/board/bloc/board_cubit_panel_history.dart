part of 'board_cubit.dart';

extension BoardCubitPanelHistory on BoardCubit {
  int redoDepthForBoard(String boardId) => _redoStacks[boardId]?.length ?? 0;
  Future<bool> undoLatestPanelHistory(String boardId) async {
    return _runHistoryReplay(() async {
      if (!state.boards.any((board) => board.id == boardId)) return false;
      final events = await _historyStore.eventsForBoard(boardId);
  
      for (var index = events.length - 1; index >= 0; index--) {
        final event = events[index];
        if (event.entityType != 'panel') continue;
        if (event.restoresOpId != null || event.type == 'panel.restored') {
          continue;
        }
  
        final current = state.boards
            .firstWhereOrNull((board) => board.id == boardId)
            ?.panels
            .firstWhereOrNull((panel) => panel.id == event.entityId);
        final before =
            event.before == null
                ? null
                : _panelFromHistorySnapshot(event.before!);
        final after =
            event.after == null
                ? null
                : _panelFromHistorySnapshot(event.after!);
  
        if (after != null &&
            before == null &&
            current != null &&
            _panelMatchesCreateUndo(current, after)) {
          _pushRedo(boardId, BoardRedoEntry.recreate(after));
          await removePanel(
            after.id,
            boardId: boardId,
            recordHistory: false,
          );
          return true;
        }
        if (before != null &&
            current != null &&
            !_panelSnapshotsMatch(current, before)) {
          final coalescedEvent = _coalescedPanelUpdateStart(events, index);
          final coalescedBefore = coalescedEvent.before;
          final snapshot =
              coalescedBefore == null
                  ? before
                  : _panelFromHistorySnapshot(coalescedBefore);
          final latestAfter =
              event.after == null
                  ? null
                  : _panelFromHistorySnapshot(event.after!);
          if (latestAfter != null) {
            _pushRedo(boardId, BoardRedoEntry.restore(latestAfter));
          }
          return _restorePanelSnapshot(
            boardId: boardId,
            panelFromEvent: snapshot,
            restoresOpId: event.opId,
          );
        }
        if (before != null &&
            current == null &&
            event.type == 'panel.deleted') {
          _pushRedo(boardId, BoardRedoEntry.delete(event.entityId));
          return restorePanelFromEvent(boardId, event.opId);
        }
      }
  
      return false;
    });
  }
  
  Future<bool> redoLatestPanelHistory(String boardId) async {
    final stack = _redoStacks[boardId];
    if (stack == null || stack.isEmpty) return false;
    if (!state.boards.any((board) => board.id == boardId)) return false;
  
    final entry = stack.removeLast();
    if (stack.isEmpty) {
      _redoStacks.remove(boardId);
    }
  
    return _runHistoryReplay(() async {
      switch (entry.kind) {
        case BoardRedoKind.recreatePanel:
          final panel = entry.panel;
          if (panel == null) return false;
          await addPanel(panel, boardId: boardId);
          await focusPanel(panel.id, boardId: boardId);
          return true;
        case BoardRedoKind.restorePanel:
          final panel = entry.panel;
          if (panel == null) return false;
          return _applyPanelSnapshot(boardId: boardId, panel: panel);
        case BoardRedoKind.deletePanel:
          final panelId = entry.panelId;
          if (panelId == null) return false;
          await removePanel(panelId, boardId: boardId);
          return true;
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
  
  void _pushRedo(String boardId, BoardRedoEntry entry) {
    final stack = _redoStacks.putIfAbsent(boardId, () => <BoardRedoEntry>[]);
    stack.add(entry);
  }
  
  Future<bool> _applyPanelSnapshot({
    required String boardId,
    required BoardPanelInstance panel,
  }) async {
    final current = state.boards
        .firstWhereOrNull((board) => board.id == boardId)
        ?.panels
        .firstWhereOrNull((entry) => entry.id == panel.id);
    if (current != null && _panelSnapshotsMatch(current, panel)) {
      return false;
    }
    if (current != null) {
      await updatePanel(panel.id, (_) => panel, boardId: boardId);
      return true;
    }
    await addPanel(panel, boardId: boardId);
    await focusPanel(panel.id, boardId: boardId);
    return true;
  }
  
  BoardHistoryEvent _coalescedPanelUpdateStart(
    List<BoardHistoryEvent> events,
    int latestIndex,
  ) {
    final latest = events[latestIndex];
    if (!_isCoalescablePanelMutation(latest)) return latest;
    var start = latestIndex;
    final signature = _patchSignature(latest);
    while (start > 0) {
      final previous = events[start - 1];
      if (!_isCoalescablePanelMutation(previous) ||
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
  
  bool _isCoalescablePanelMutation(BoardHistoryEvent event) {
    return event.type == 'panel.updated' || event.type == 'panel.placedInGrid';
  }
  
  bool _panelMatchesCreateUndo(
    BoardPanelInstance current,
    BoardPanelInstance after,
  ) {
    final currentSnap = Map<String, dynamic>.from(_panelSnapshot(current));
    final afterSnap = Map<String, dynamic>.from(_panelSnapshot(after));
    currentSnap.remove('zIndex');
    afterSnap.remove('zIndex');
    return jsonEncode(currentSnap) == jsonEncode(afterSnap);
  }
  
  String _patchSignature(BoardHistoryEvent event) {
    final keys = event.patch.keys.toList()..sort();
    return keys.join('|');
  }
  
  bool _panelSnapshotsMatch(
    BoardPanelInstance current,
    BoardPanelInstance snapshot,
  ) {
    return jsonEncode(_panelSnapshot(current)) ==
        jsonEncode(_panelSnapshot(snapshot));
  }
  /// Captures the panel snapshot at the start of a drag/resize gesture.
  void beginPanelGesture(String panelId, {String? boardId}) {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    final panel = state.boards
        .firstWhereOrNull((board) => board.id == targetId)
        ?.panels
        .firstWhereOrNull((entry) => entry.id == panelId);
    if (panel == null) return;
    _panelGestureStarts[panelId] = panel;
  }
  
  /// Records one history step for a completed drag/resize gesture.
  Future<void> endPanelGesture(String panelId, {String? boardId}) async {
    final start = _panelGestureStarts.remove(panelId);
    if (start == null) return;
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    final current = state.boards
        .firstWhereOrNull((board) => board.id == targetId)
        ?.panels
        .firstWhereOrNull((entry) => entry.id == panelId);
    if (current == null) return;
    if (_panelSnapshotsMatch(current, start)) return;
    await _appendPanelUpdateHistory(
      boardId: targetId,
      beforePanel: start,
      afterPanel: current,
    );
  }
}
