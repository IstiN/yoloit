import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class BoardCubit extends Cubit<BoardState> {
  BoardCubit() : super(const BoardState());

  static const _boardsStorageKey = 'board.documents.v1';
  static const _activeBoardStorageKey = 'board.active.id.v1';

  Future<void> load() async {
    if (state.isLoaded) return;
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

  Future<void> setActiveBoard(String id) async {
    if (!state.boards.any((board) => board.id == id)) return;
    await _setBoards(state.boards, activeBoardId: id);
  }

  Future<void> renameBoard(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _updateBoard(id, (board) => board.copyWith(name: trimmed));
  }

  Future<void> deleteBoard(String id) async {
    if (state.boards.isEmpty) return;
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

  Future<void> updateViewport(BoardViewport viewport, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) => board.copyWith(viewport: viewport));
  }

  Future<void> focusPanel(String panelId, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      final maxZ = board.panels.fold<int>(
        0,
        (value, panel) => panel.zIndex > value ? panel.zIndex : value,
      );
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
        viewport: board.viewport.copyWith(focusedPanelId: panelId),
      );
    });
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

  Future<void> addPanel(BoardPanelInstance panel, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(
      targetId,
      (board) => board.copyWith(panels: [...board.panels, panel]),
    );
  }

  Future<void> updatePanel(
    String panelId,
    BoardPanelInstance Function(BoardPanelInstance panel) update, {
    String? boardId,
  }) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      final updatedPanels =
          board.panels
              .map((panel) => panel.id == panelId ? update(panel) : panel)
              .toList();
      return board.copyWith(panels: updatedPanels);
    });
  }

  Future<void> movePanel(
    String panelId,
    Offset delta, {
    String? boardId,
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

  Future<void> removePanel(String panelId, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
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
    });
  }

  Future<void> upsertLink(BoardPanelLink link, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      final updated = [
        ...board.links.where((entry) => entry.id != link.id),
        link,
      ];
      return board.copyWith(links: updated);
    });
  }

  Future<void> removeLink(String linkId, {String? boardId}) async {
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      final updated = board.links.where((link) => link.id != linkId).toList();
      return board.copyWith(links: updated);
    });
  }

  Future<void> _updateBoard(
    String boardId,
    BoardDocument Function(BoardDocument board) update,
  ) async {
    final boards = state.boards;
    final index = boards.indexWhere((board) => board.id == boardId);
    if (index == -1) return;
    final updatedBoards = [...boards];
    updatedBoards[index] = update(updatedBoards[index]);
    await _setBoards(
      updatedBoards,
      activeBoardId: state.activeBoardId ?? boardId,
    );
  }

  Future<void> _setBoards(
    List<BoardDocument> boards, {
    required String? activeBoardId,
  }) async {
    emit(
      state.copyWith(
        boards: boards,
        activeBoardId: activeBoardId,
        isLoaded: true,
      ),
    );
    await _persist(boards: boards, activeBoardId: activeBoardId);
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

  BoardDocument _buildDefaultBoard({required String name}) {
    return BoardDocument(
      id: _nextId('board'),
      name: name,
      metadata: const {'version': 1},
    );
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

  BoardPanelBounds _nextAvailableBounds(
    BoardDocument board, {
    required double preferredWidth,
    required double preferredHeight,
  }) {
    const startX = 120.0;
    const startY = 120.0;
    const gap = 24.0;
    const stepX = 56.0;
    const stepY = 42.0;
    const maxColumns = 8;

    final occupiedRects =
        board.panels
            .where((panel) => !panel.hidden)
            .map((panel) => panel.bounds.rect.inflate(gap))
            .toList();

    for (var row = 0; row < 40; row++) {
      for (var column = 0; column < maxColumns; column++) {
        final candidate = Rect.fromLTWH(
          startX + (column * (preferredWidth + stepX)),
          startY + (row * (preferredHeight + stepY)),
          preferredWidth,
          preferredHeight,
        );
        final overlaps = occupiedRects.any(candidate.overlaps);
        if (!overlaps) {
          return BoardPanelBounds(
            x: candidate.left,
            y: candidate.top,
            width: preferredWidth,
            height: preferredHeight,
          );
        }
      }
    }

    return BoardPanelBounds(
      x: startX,
      y: startY + (occupiedRects.length * (preferredHeight + stepY) * 0.35),
      width: preferredWidth,
      height: preferredHeight,
    );
  }
}
