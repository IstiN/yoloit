part of 'board_cubit.dart';

extension BoardCubitPanelHistory on BoardCubit {
  int redoDepthForBoard(String boardId) => _redoStacks[boardId]?.length ?? 0;
  Future<bool> undoLatestPanelHistory(String boardId) async {
    return _runHistoryReplay(() async {
      if (!state.boards.any((board) => board.id == boardId)) return false;
      final events = await _historyStore.eventsForBoard(boardId);

      final plan = planPanelHistoryUndo<BoardPanelInstance>(
        events: events,
        currentPanelOf:
            (entityId) => state.boards
                .firstWhereOrNull((board) => board.id == boardId)
                ?.panels
                .firstWhereOrNull((panel) => panel.id == entityId),
        panelFromJson: _panelFromHistorySnapshot,
        panelToJson: _panelSnapshot,
      );

      switch (plan.kind) {
        case PanelUndoKind.none:
          return false;
        case PanelUndoKind.removeCreated:
          final after = plan.snapshot!;
          _pushRedo(boardId, BoardRedoEntry.recreate(after));
          await removePanel(
            after.id,
            boardId: boardId,
            recordHistory: false,
          );
          return true;
        case PanelUndoKind.restoreSnapshot:
          final latestAfter = plan.redoSnapshot;
          if (latestAfter != null) {
            _pushRedo(boardId, BoardRedoEntry.restore(latestAfter));
          }
          return _restorePanelSnapshot(
            boardId: boardId,
            panelFromEvent: plan.snapshot!,
            restoresOpId: plan.opId!,
          );
        case PanelUndoKind.restoreDeleted:
          _pushRedo(boardId, BoardRedoEntry.delete(plan.entityId!));
          return restorePanelFromEvent(boardId, plan.opId!);
      }
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
  
  bool _panelSnapshotsMatch(
    BoardPanelInstance current,
    BoardPanelInstance snapshot,
  ) {
    return panelSnapshotsEqual(current, snapshot, _panelSnapshot);
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
