import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_plugin.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/provider_model_catalog_service.dart';

class BoardCubit extends Cubit<BoardState> {
  BoardCubit({BoardHistoryStore? historyStore, String actorId = 'local'})
    : _historyStore = historyStore ?? const NoopBoardHistoryStore(),
      _actorId = actorId,
      super(const BoardState());

  static const _boardsStorageKey = 'board.documents.v1';
  static const _activeBoardStorageKey = 'board.active.id.v1';

  final BoardHistoryStore _historyStore;
  final String _actorId;

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
        debugPrint('[BoardCubit] removed duplicate-ID panels, re-saving');
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

  Future<List<BoardHistoryEvent>> historyForBoard(String boardId) {
    return _historyStore.eventsForBoard(boardId);
  }

  Future<bool> restorePanelFromEvent(String boardId, String opId) async {
    final event = await _historyStore.eventById(boardId, opId);
    if (event == null || event.entityType != 'panel') return false;
    final snapshot = event.before ?? event.after;
    if (snapshot == null) return false;
    final panelFromEvent = _panelFromHistorySnapshot(snapshot);
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
          restoresOpId: opId,
        );
      },
    );
    return restored;
  }

  Future<void> setActiveBoard(String id) async {
    if (!state.boards.any((board) => board.id == id)) return;
    await _setBoards(state.boards, activeBoardId: id);
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
    if (targetId == null) return;
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
    final targetId = boardId ?? state.activeBoard?.id;
    if (targetId == null) return;
    await _updateBoard(targetId, (board) {
      if (board.viewport.focusedPanelId == null) {
        return board;
      }
      return board.copyWith(
        viewport: board.viewport.copyWith(clearFocusedPanelId: true),
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

  Future<void> createChatPanel({
    String? title,
    String? sessionName,
    String workingDir = '',
    String model = 'gpt-5-mini',
    String provider = 'copilot',
    List<String> envGroupIds = const [],
    List<Map<String, dynamic>>? messages,
  }) async {
    final board = state.activeBoard;
    if (board == null) return;
    final bounds = _nextAvailableBounds(
      board,
      preferredWidth: 420,
      preferredHeight: 500,
    );

    // Resolve effective model: user's explicit arg → agent default model → catalog default → hardcoded default
    final effectiveModel = _resolveDefaultModel(provider, model);
    final effectiveWorkingDir = _effectiveBoardFolder(board, workingDir);

    final config = ChatSessionConfig(
      sessionName:
          sessionName ?? 'chat-${DateTime.now().millisecondsSinceEpoch}',
      workingDir: effectiveWorkingDir,
      model: effectiveModel,
      provider: provider,
      envGroupIds: envGroupIds,
    );
    final panelState = <String, dynamic>{
      'config': config.toJson(),
      'configured': effectiveWorkingDir.trim().isNotEmpty,
    };
    if (messages != null && messages.isNotEmpty) {
      panelState['messages'] = messages;
    }
    final panel = BoardPanelInstance(
      id: _nextId('panel'),
      type: ChatPanelPlugin.kTypeId,
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
      type: BoardTerminalPanelPlugin.kTypeId,
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
      historyEvent: (before, after, revision) {
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
      },
    );
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

  Future<void> removePanel(String panelId, {String? boardId}) async {
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
      historyEvent: (before, after, revision) {
        final removedPanel = before.panels.firstWhereOrNull(
          (panel) => panel.id == panelId,
        );
        if (removedPanel == null) return null;
        final removedLinks =
            before.links
                .where(
                  (link) =>
                      link.fromPanelId == panelId || link.toPanelId == panelId,
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
      },
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
    try {
      await _historyStore.append(event);
    } catch (error, stackTrace) {
      debugPrint('[BoardCubit] failed to append board history: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  int _historyRevision(BoardDocument board) {
    return (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
  }

  BoardDocument _withHistoryRevision(BoardDocument board, int revision) {
    return board.copyWith(
      metadata: {...board.metadata, 'historyRevision': revision},
    );
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
    final defaultFolder = board.defaultFolder;
    if (defaultFolder.isEmpty) return initialState;
    if (typeId == 'board.filetree') {
      return {...initialState, 'rootPath': defaultFolder};
    }
    if (typeId == ChatPanelPlugin.kTypeId) {
      final rawConfig = initialState['config'];
      final config = ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(rawConfig is Map ? rawConfig : const {}),
      );
      return {
        ...initialState,
        'config': config.copyWith(workingDir: defaultFolder).toJson(),
        'configured': true,
      };
    }
    if (typeId == BoardTerminalPanelPlugin.kTypeId) {
      final rawConfig = initialState['config'];
      final config = BoardTerminalConfig.fromJson(
        Map<String, dynamic>.from(rawConfig is Map ? rawConfig : const {}),
      );
      return {
        ...initialState,
        'config': config.copyWith(workingDir: defaultFolder).toJson(),
      };
    }
    return initialState;
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

extension _BoardCubitIterable<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T value) test) {
    for (final value in this) {
      if (test(value)) return value;
    }
    return null;
  }
}
