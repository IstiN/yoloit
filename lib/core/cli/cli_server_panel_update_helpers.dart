part of 'cli_server.dart';

/// Per-field and per-step helpers for [CliServer._updatePanel],
/// [CliServer._panelAction], [CliServer._applyYaml] and
/// [CliServer._applyYamlPanelUpdates]. Each helper owns its own guard so the
/// callers stay linear; the extraction is behavior-preserving (conditions and
/// their order are unchanged, bodies moved verbatim).
extension _PanelUpdateHelpers on CliServer {
  // ── HTTP panel update (`_updatePanel`) ──────────────────────────────────

  Future<void> _applyPanelTitleUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('title')) {
      await cubit.updatePanelTitle(
        panel.id,
        body['title'] as String,
        boardId: board.id,
      );
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelMoveUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('x') || body.containsKey('y')) {
      final dx =
          ((body['x'] as num?)?.toDouble() ?? panel.bounds.x) - panel.bounds.x;
      final dy =
          ((body['y'] as num?)?.toDouble() ?? panel.bounds.y) - panel.bounds.y;
      await cubit.movePanel(panel.id, Offset(dx, dy), boardId: board.id);
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelResizeUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('width') || body.containsKey('height')) {
      await cubit.resizePanel(
        panel.id,
        width: (body['width'] as num?)?.toDouble() ?? panel.bounds.width,
        height: (body['height'] as num?)?.toDouble() ?? panel.bounds.height,
        boardId: board.id,
      );
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelFocusUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body['focus'] == true) {
      if (cubit.state.activeBoardId != board.id) {
        await cubit.setActiveBoard(board.id);
      }
      await cubit.focusPanel(panel.id, boardId: board.id, zoomOnFocus: true);
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelColorUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('color')) {
      final colorStr = body['color'] as String?;
      final parsed = colorStr == 'clear' ? null : parseColor(colorStr);
      await cubit.updatePanelColor(panel.id, color: parsed, boardId: board.id);
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelHiddenUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('hidden')) {
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(hidden: body['hidden'] as bool),
        boardId: board.id,
      );
      cliScheduleRebuild();
    }
  }

  Future<void> _applyPanelZIndexUpdate(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) async {
    if (body.containsKey('zIndex')) {
      await cubit.updatePanel(
        panel.id,
        (p) =>
            p.copyWith(zIndex: (body['zIndex'] as num?)?.toInt() ?? p.zIndex),
        boardId: board.id,
      );
      cliScheduleRebuild();
    }
  }

  // ── Panel action (`_panelAction`) ───────────────────────────────────────

  /// Builds the resolved action args (board/panel context summaries included)
  /// for a panel action request body.
  Map<String, dynamic> _resolvePanelActionArgs(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  ) {
    return CliTextArgumentResolver.resolveActionArgs({
      ...body,
      '_boardId': board.id,
      '_boardName': board.name,
      '_panelType': panel.type,
      '_availableBoardsSummary': cubit.state.boards
          .map((b) => _boardSummaryLine(b, board))
          .join('\n'),
      '_currentBoardPanelsSummary': board.panels
          .map((p) => '- ${p.title} [${p.type}] (${p.id})')
          .join('\n'),
      '_currentBoardPanels': board.panels.map((p) => p.toJson()).toList(),
    });
  }

  String _boardSummaryLine(BoardDocument b, BoardDocument current) {
    final marker = b.id == current.id ? ' (current)' : '';
    return '- ${b.name} [${b.id}]$marker';
  }

  /// Applies the state updates carried by a successful panel action result.
  Future<void> _applyPanelActionResult(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    CliActionResult result,
  ) async {
    // Apply state update if provided
    if (result.stateUpdate != null && result.ok) {
      await _applyPanelActionStateUpdate(
        cubit,
        board,
        panel,
        result.stateUpdate!,
      );
      cliScheduleRebuild();
    }

    // Apply optional state updates to other panels on the same board.
    if (result.additionalStateUpdates != null && result.ok) {
      for (final entry in result.additionalStateUpdates!.entries) {
        BoardPanelInstance? targetPanel;
        for (final p in board.panels) {
          if (p.id == entry.key) {
            targetPanel = p;
            break;
          }
        }
        if (targetPanel == null) continue;
        await cubit.updatePanel(
          targetPanel.id,
          (p) => p.copyWith(state: {...targetPanel!.state, ...entry.value}),
          boardId: board.id,
        );
      }
      cliScheduleRebuild();
    }
  }

  // ── YAML bulk apply (`_applyYaml`) ──────────────────────────────────────

  shelf.Response _yamlOperationFailure(
    int index,
    Map<String, dynamic> result,
    List<Map<String, dynamic>> results,
  ) {
    return _yamlError(
      'Operation $index failed: ${result['error'] ?? result['message'] ?? 'unknown error'}',
      details: {'failedAt': index, 'results': results},
    );
  }

  /// Mirrors the board-level effect of a successful `panel.create` /
  /// `panel.delete` operation onto [currentBoard] for subsequent operations.
  BoardDocument _yamlBoardAfterOperation(
    BoardDocument currentBoard,
    Map<String, dynamic> opMap,
    Map<String, dynamic> result,
    Map<String, BoardPanelInstance> pendingPanels,
  ) {
    if (opMap['op'] == 'panel.create' || opMap['action'] == 'panel.create') {
      final panelId = _string(result['panelId']);
      final created = panelId == null ? null : pendingPanels[panelId];
      if (created != null) {
        return currentBoard.copyWith(
          panels: [...currentBoard.panels, created],
        );
      }
    } else if (opMap['op'] == 'panel.delete' ||
        opMap['action'] == 'panel.delete') {
      final panelId = _string(result['panelId']);
      if (panelId != null) {
        return currentBoard.copyWith(
          panels: currentBoard.panels
              .where((panel) => panel.id != panelId)
              .toList(),
        );
      }
    }
    return currentBoard;
  }

  // ── YAML panel.update apply (`_applyYamlPanelUpdates`) ──────────────────

  Future<void> _yamlApplyPanelTitle(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('title')) {
      await cubit.updatePanelTitle(
        panel.id,
        updates['title'] as String,
        boardId: board.id,
      );
    }
  }

  Future<void> _yamlApplyPanelPosition(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('x') || updates.containsKey('y')) {
      final x = (updates['x'] as num?)?.toDouble() ?? panel.bounds.x;
      final y = (updates['y'] as num?)?.toDouble() ?? panel.bounds.y;
      await cubit.movePanel(
        panel.id,
        Offset(x - panel.bounds.x, y - panel.bounds.y),
        boardId: board.id,
      );
    }
  }

  Future<void> _yamlApplyPanelSize(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('width') || updates.containsKey('height')) {
      await cubit.resizePanel(
        panel.id,
        width: (updates['width'] as num?)?.toDouble() ?? panel.bounds.width,
        height: (updates['height'] as num?)?.toDouble() ?? panel.bounds.height,
        boardId: board.id,
      );
    }
  }

  Future<void> _yamlApplyPanelHidden(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('hidden')) {
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(hidden: updates['hidden'] as bool),
        boardId: board.id,
      );
    }
  }

  Future<void> _yamlApplyPanelAttributes(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> updates,
  ) async {
    if (updates.containsKey('locked') ||
        updates.containsKey('pinned') ||
        updates.containsKey('params') ||
        updates.containsKey('state') ||
        updates.containsKey('zIndex') ||
        updates.containsKey('color')) {
      final color = updates['color'] as Color?;
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(
          color: updates.containsKey('color') && color == null ? null : color,
          clearColor: updates.containsKey('color') && color == null,
          params: updates['params'] as Map<String, dynamic>? ?? p.params,
          state: updates['state'] as Map<String, dynamic>? ?? p.state,
          zIndex: updates['zIndex'] as int? ?? p.zIndex,
          locked: updates['locked'] as bool? ?? p.locked,
          pinned: updates['pinned'] as bool? ?? p.pinned,
        ),
        boardId: board.id,
      );
    }
  }
}
