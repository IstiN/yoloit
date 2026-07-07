import 'dart:async';

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Lightweight fake [BoardCubit] for unit-testing web chat tool executor.
class FakeBoardCubit extends BoardCubit {
  FakeBoardCubit() : super() {
    const board = BoardDocument(
      id: 'b-1',
      name: 'Test Board',
      panels: [],
    );
    emit(state.copyWith(boards: [board], activeBoardId: board.id));
  }

  final List<Map<String, dynamic>> createdNotes = [];
  final List<BoardPanelInstance> createdGenericPanels = [];
  final Map<String, BoardPanelInstance> updatedPanels = {};
  final List<String> focusedPanelIds = [];
  String? activeBoardId;
  final List<BoardPanelLink> upsertedLinks = [];
  final List<BoardPanelGroup> createdGroups = [];
  final List<BoardDrawingElement> addedDrawings = [];
  final List<String> removedDrawingIds = [];
  final List<String> removedLinkIds = [];

  void addFakePanel(BoardPanelInstance panel) {
    final board = state.activeBoard!;
    emit(
      state.copyWith(
        boards: [
          board.copyWith(panels: [...board.panels, panel]),
        ],
      ),
    );
  }

  void addFakeBoard(BoardDocument board) {
    emit(state.copyWith(boards: [...state.boards, board]));
  }

  void _updateActiveBoard(BoardDocument Function(BoardDocument board) update) {
    final board = state.activeBoard;
    if (board == null) return;
    final updated = update(board);
    emit(
      state.copyWith(
        boards:
            state.boards.map((b) => b.id == board.id ? updated : b).toList(),
      ),
    );
  }

  @override
  Future<void> createMarkdownNote({
    required String title,
    required String markdown,
  }) async {
    createdNotes.add({'title': title, 'markdown': markdown});
  }

  @override
  Future<void> createGenericPanel(
    String typeId, {
    String? title,
    Map<String, dynamic> panelState = const {},
    Size? preferredSize,
  }) async {
    final panel = BoardPanelInstance(
      id: 'panel-${createdGenericPanels.length}',
      type: typeId,
      title: title ?? typeId,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
      state: panelState,
    );
    createdGenericPanels.add(panel);
    addFakePanel(panel);
  }

  @override
  Future<void> addPanel(
    BoardPanelInstance panel, {
    String? boardId,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    emit(
      state.copyWith(
        boards:
            state.boards
                .map(
                  (b) => b.id == targetId
                      ? b.copyWith(panels: [...b.panels, panel])
                      : b,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> updatePanel(
    String panelId,
    BoardPanelInstance Function(BoardPanelInstance panel) update, {
    String? boardId,
    bool recordHistory = true,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    final board = state.boards.firstWhere((b) => b.id == targetId);
    final panel = board.panels.firstWhere((p) => p.id == panelId);
    final updated = update(panel);
    updatedPanels[panelId] = updated;
    emit(
      state.copyWith(
        boards: [
          board.copyWith(
            panels: board.panels.map((p) => p.id == panelId ? updated : p).toList(),
          ),
        ],
      ),
    );
  }

  @override
  Future<void> removePanel(
    String panelId, {
    String? boardId,
    bool recordHistory = true,
  }) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        panels: board.panels.where((p) => p.id != panelId).toList(),
        links:
            board.links
                .where(
                  (l) => l.fromPanelId != panelId && l.toPanelId != panelId,
                )
                .toList(),
      ),
    );
  }

  @override
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

  @override
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

  @override
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

  @override
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

  @override
  Future<void> updatePanelTitle(
    String panelId,
    String title, {
    String? boardId,
  }) async {
    await updatePanel(panelId, (panel) => panel.copyWith(title: title), boardId: boardId);
  }

  @override
  Future<void> focusPanel(
    String panelId, {
    String? boardId,
    bool zoomOnFocus = false,
  }) async {
    focusedPanelIds.add(panelId);
  }

  @override
  Future<void> setActiveBoard(String id) async {
    activeBoardId = id;
    emit(state.copyWith(activeBoardId: id, clearSelection: true));
  }

  @override
  Future<void> upsertLink(BoardPanelLink link, {String? boardId}) async {
    upsertedLinks.add(link);
    _updateActiveBoard(
      (board) => board.copyWith(
        links: [
          ...board.links.where((l) => l.id != link.id),
          link,
        ],
      ),
    );
  }

  @override
  Future<void> removeLink(String linkId, {String? boardId}) async {
    removedLinkIds.add(linkId);
    _updateActiveBoard(
      (board) => board.copyWith(
        links: board.links.where((l) => l.id != linkId).toList(),
      ),
    );
  }

  @override
  Future<BoardDocument?> createBoard({String? name}) async {
    final board = BoardDocument(
      id: 'board-${state.boards.length}',
      name: name ?? 'Board ${state.boards.length + 1}',
      panels: [],
    );
    emit(
      state.copyWith(boards: [...state.boards, board], activeBoardId: board.id),
    );
    return board;
  }

  @override
  Future<void> renameBoard(String id, String name) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map((b) => b.id == id ? b.copyWith(name: name.trim()) : b)
                .toList(),
      ),
    );
  }

  @override
  Future<void> deleteBoard(String id) async {
    final updated = state.boards.where((b) => b.id != id).toList();
    emit(
      state.copyWith(
        boards: updated.isEmpty ? state.boards : updated,
        activeBoardId:
            state.activeBoardId == id
                ? (updated.isEmpty ? null : updated.first.id)
                : state.activeBoardId,
      ),
    );
  }

  @override
  Future<void> archiveBoard(String id) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map((b) => b.id == id ? b.copyWith(archived: true) : b)
                .toList(),
      ),
    );
  }

  @override
  Future<void> unarchiveBoard(String id) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map((b) => b.id == id ? b.copyWith(archived: false) : b)
                .toList(),
      ),
    );
  }

  @override
  Future<void> updateViewport(BoardViewport viewport, {String? boardId}) async {
    _updateActiveBoard((board) => board.copyWith(viewport: viewport));
  }

  @override
  Future<void> setGridMode(String boardId, {required bool enabled}) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map(
                  (b) => b.id == boardId
                      ? b.copyWithGridMode(
                        b.gridMode.copyWith(enabled: enabled),
                      )
                      : b,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> setGridCellSize(String boardId, double cellSize) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map(
                  (b) => b.id == boardId
                      ? b.copyWithGridMode(
                        b.gridMode.copyWith(cellSize: cellSize),
                      )
                      : b,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> setGridSpacing(String boardId, double spacing) async {
    emit(
      state.copyWith(
        boards:
            state.boards
                .map(
                  (b) => b.id == boardId
                      ? b.copyWithGridMode(
                        b.gridMode.copyWith(spacing: spacing),
                      )
                      : b,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> arrangePanelsInGrid(String boardId) async {}

  @override
  Future<void> arrangePanelsByTypeInGrid(String boardId) async {}

  @override
  Future<void> resetGridView(String boardId) async {}

  @override
  Future<void> createGroup(
    String boardId, {
    required String name,
    List<String> panelIds = const [],
    int? color,
  }) async {
    final group = BoardPanelGroup(
      id: 'group-${createdGroups.length}',
      name: name,
      color: color,
      panelIds: panelIds,
    );
    createdGroups.add(group);
    emit(
      state.copyWith(
        boards:
            state.boards
                .map(
                  (b) => b.id == boardId
                      ? b.copyWith(groups: [...b.groups, group])
                      : b,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> deleteGroup(String boardId, String groupId) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups: board.groups.where((g) => g.id != groupId).toList(),
      ),
    );
  }

  @override
  Future<void> renameGroup(
    String boardId,
    String groupId,
    String name,
  ) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups:
            board.groups
                .map((g) => g.id == groupId ? g.copyWith(name: name) : g)
                .toList(),
      ),
    );
  }

  @override
  Future<void> setGroupColor(
    String boardId,
    String groupId,
    int? color,
  ) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups:
            board.groups
                .map(
                  (g) => g.id == groupId
                      ? g.copyWith(
                        color: color,
                        clearColor: color == null,
                      )
                      : g,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> addPanelsToGroup(
    String boardId,
    String groupId,
    List<String> panelIds,
  ) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups:
            board.groups
                .map(
                  (g) => g.id == groupId
                      ? g.copyWith(
                        panelIds: {
                          ...g.panelIds,
                          ...panelIds,
                        }.toList(),
                      )
                      : g,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> removePanelsFromGroup(
    String boardId,
    String groupId,
    List<String> panelIds,
  ) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups:
            board.groups
                .map(
                  (g) => g.id == groupId
                      ? g.copyWith(
                        panelIds: g.panelIds.where((id) => !panelIds.contains(id)).toList(),
                      )
                      : g,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> toggleGroupCollapse(String boardId, String groupId) async {
    _updateActiveBoard(
      (board) => board.copyWith(
        groups:
            board.groups
                .map(
                  (g) => g.id == groupId
                      ? g.copyWith(collapsed: !g.collapsed)
                      : g,
                )
                .toList(),
      ),
    );
  }

  @override
  Future<void> moveGroup(String boardId, String groupId, Offset delta) async {
    _updateActiveBoard(
      (board) {
        final group = board.groups.firstWhere((g) => g.id == groupId);
        final ids = group.panelIds.toSet();
        return board.copyWith(
          panels:
              board.panels
                  .map(
                    (p) => ids.contains(p.id)
                        ? p.copyWith(
                          bounds: p.bounds.copyWith(
                            x: p.bounds.x + delta.dx,
                            y: p.bounds.y + delta.dy,
                          ),
                        )
                        : p,
                  )
                  .toList(),
        );
      },
    );
  }

  @override
  Future<void> cycleGroupFocus(String boardId, String groupId, int direction) async {}

  @override
  void selectPanels(Set<String> panelIds) {
    emit(state.copyWith(selectedPanelIds: panelIds));
  }

  @override
  void selectPanelsInRect(Rect rect) {
    final board = state.activeBoard;
    if (board == null) return;
    final ids =
        board.panels
            .where(
              (p) =>
                  Rect.fromLTWH(
                    p.bounds.x,
                    p.bounds.y,
                    p.bounds.width,
                    p.bounds.height,
                  ).overlaps(rect),
            )
            .map((p) => p.id)
            .toSet();
    emit(state.copyWith(selectedPanelIds: ids));
  }

  @override
  void clearSelection() {
    emit(state.copyWith(clearSelection: true));
  }

  @override
  Future<void> addDrawing(
    BoardDrawingElement drawing, {
    String? boardId,
  }) async {
    addedDrawings.add(drawing);
    _updateActiveBoard(
      (board) => board.copyWith(drawings: [...board.drawings, drawing]),
    );
  }

  @override
  Future<void> removeDrawing(String drawingId, {String? boardId}) async {
    removedDrawingIds.add(drawingId);
    _updateActiveBoard(
      (board) => board.copyWith(
        drawings: board.drawings.where((d) => d.id != drawingId).toList(),
      ),
    );
  }

  Future<bool> undoLatestPanelHistory(String boardId) async => false;

  Future<bool> redoLatestPanelHistory(String boardId) async => false;
}
