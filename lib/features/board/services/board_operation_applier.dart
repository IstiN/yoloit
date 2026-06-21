import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';

/// Applies a subset of `board:apply` operations to a board.
///
/// This is used by templates and other callers that want to create panels,
/// links, and adjust the viewport declaratively without going through the
/// full YAML pipeline.
///
/// Supported operations:
/// - `panel.create`
/// - `link.create`
/// - `board.configure` (name, defaultFolder, archived)
/// - `board.fit`
/// - `board.arrange`
///
/// Unsupported operations are ignored so that callers remain forward
/// compatible.
class BoardOperationApplier {
  const BoardOperationApplier();

  /// Applies [operations] to [board] using [cubit] and returns the updated
  /// board. The board is assumed to already exist in [cubit.state].
  Future<BoardDocument> apply(
    BoardCubit cubit,
    BoardDocument board,
    List<Map<String, dynamic>> operations,
  ) async {
    final result = _applyOperations(
      board,
      operations,
      onPanel: (panel) => cubit.addPanel(panel, boardId: board.id),
      onLink: (link) => cubit.upsertLink(link, boardId: board.id),
      onConfigure: (updated) async {
        final name = _string(updated['name']);
        final defaultFolder = _string(updated['defaultFolder']);
        final archived = _bool(updated['archived']);
        if (name != null && name.isNotEmpty) {
          await cubit.renameBoard(board.id, name);
        }
        if (defaultFolder != null) {
          await cubit.updateBoardDefaultFolder(board.id, defaultFolder);
        }
        if (archived != null) {
          if (archived) {
            await cubit.archiveBoard(board.id);
          } else {
            await cubit.unarchiveBoard(board.id);
          }
        }
      },
      onFit: (viewport) => cubit.updateViewport(viewport, boardId: board.id),
      onArrange: () => cubit.arrangePanelsByTypeInGrid(board.id),
    );

    return cubit.state.boards.where((b) => b.id == board.id).firstOrNull ??
        result;
  }

  /// Builds a [BoardDocument] from [operations] without touching a real cubit.
  ///
  /// This is useful for generating previews, screenshots, or other read-only
  /// representations of a template before it is persisted.
  BoardDocument buildDocument(
    BoardDocument board,
    List<Map<String, dynamic>> operations,
  ) {
    return _applyOperations(
      board,
      operations,
      onPanel: (_) {},
      onLink: (_) {},
      onConfigure: (_) async {},
      onFit: (_) async {},
    );
  }

  /// Shared operation loop used by both [apply] and [buildDocument].
  ///
  /// Callbacks are invoked so that [apply] can persist changes through a real
  /// [BoardCubit] while [buildDocument] stays side-effect free.
  BoardDocument _applyOperations(
    BoardDocument board,
    List<Map<String, dynamic>> operations, {
    required FutureOr<void> Function(BoardPanelInstance panel) onPanel,
    required FutureOr<void> Function(BoardPanelLink link) onLink,
    required FutureOr<void> Function(Map<String, dynamic> raw) onConfigure,
    required FutureOr<void> Function(BoardViewport viewport) onFit,
    void Function()? onArrange,
  }) {
    var currentBoard = board;
    final refs = <String, String>{};
    final pendingPanels = <String, BoardPanelInstance>{};

    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      final opName = _string(op['op'] ?? op['action']);
      if (opName == null || opName.isEmpty) continue;

      switch (opName) {
        case 'panel.create':
          final panel = _buildPanel(currentBoard, refs, pendingPanels, op);
          if (panel != null) {
            onPanel(panel);
            currentBoard = currentBoard.copyWith(
              panels: [...currentBoard.panels, panel],
            );
          }
        case 'link.create':
          final link = _buildLink(currentBoard, refs, op);
          if (link != null) {
            onLink(link);
            currentBoard = currentBoard.copyWith(
              links: [...currentBoard.links, link],
            );
          }
        case 'board.configure':
          currentBoard = _applyBoardConfigure(currentBoard, op);
          onConfigure(op);
        case 'board.fit':
          final viewport = _fitViewport(currentBoard, op);
          onFit(viewport);
          currentBoard = currentBoard.copyWith(viewport: viewport);
        case 'board.arrange':
          onArrange?.call();
      }
    }

    return currentBoard;
  }

  /// Builds a panel from a `panel.create` operation without mutating any cubit.
  BoardPanelInstance? _buildPanel(
    BoardDocument board,
    Map<String, String> refs,
    Map<String, BoardPanelInstance> pendingPanels,
    Map<String, dynamic> raw,
  ) {
    final typeId = _string(raw['type'] ?? raw['typeId']);
    if (typeId == null) return null;

    final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
    if (plugin == null) return null;

    final title = _string(raw['title']) ?? plugin.displayName;
    final x = _double(raw['x']) ?? 100.0;
    final y = _double(raw['y']) ?? 100.0;
    final width = _double(raw['width']) ?? plugin.defaultSize.width;
    final height = _double(raw['height']) ?? plugin.defaultSize.height;
    final state = _map(raw['state']);
    final params = _map(raw['params']);
    final ref = _string(raw['ref']);
    final color = _color(raw['color']);
    final hidden = _bool(raw['hidden']) ?? false;
    final locked = _bool(raw['locked']) ?? false;
    final pinned = _bool(raw['pinned']) ?? false;
    final panelId = _string(raw['id'] ?? raw['panelId']) ?? _nextId('p');
    final zIndex = board.panels.fold<int>(
          0,
          (value, panel) => panel.zIndex > value ? panel.zIndex : value,
        ) +
        1;

    final panel = BoardPanelInstance(
      id: panelId,
      type: typeId,
      title: title.trim().isEmpty ? plugin.displayName : title.trim(),
      bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
      color: color,
      params: {...?params, if (ref != null && ref.isNotEmpty) 'yamlRef': ref},
      state: {...plugin.initialState, if (state != null) ...state},
      zIndex: zIndex,
      hidden: hidden,
      locked: locked,
      pinned: pinned,
    );

    pendingPanels[panel.id] = panel;
    if (ref != null && ref.isNotEmpty) {
      refs[ref] = panel.id;
      pendingPanels[ref] = panel;
    }
    return panel;
  }

  /// Builds a link from a `link.create` operation without mutating any cubit.
  BoardPanelLink? _buildLink(
    BoardDocument board,
    Map<String, String> refs,
    Map<String, dynamic> raw,
  ) {
    final fromId = _resolvePanelId(raw['from'] ?? raw['fromPanelId'], refs);
    final toId = _resolvePanelId(raw['to'] ?? raw['toPanelId'], refs);
    if (fromId == null || toId == null) return null;

    final ids = board.panels.map((p) => p.id).toSet();
    if (!ids.contains(fromId) || !ids.contains(toId)) return null;

    final style = _string(raw['style']) ?? 'arrow';
    final geometry = _string(raw['geometry']) ?? 'bezier';
    return BoardPanelLink(
      id: _nextId('link'),
      fromPanelId: fromId,
      toPanelId: toId,
      style: BoardLinkStyle.values.firstWhere(
        (s) => s.name == style,
        orElse: () => BoardLinkStyle.arrow,
      ),
      geometry: BoardLinkGeometry.values.firstWhere(
        (g) => g.name == geometry,
        orElse: () => BoardLinkGeometry.bezier,
      ),
      color: _color(raw['color']) ?? kDefaultLinkColor,
    );
  }

  /// Applies `board.configure` fields to a board document without side effects.
  BoardDocument _applyBoardConfigure(
    BoardDocument board,
    Map<String, dynamic> raw,
  ) {
    final name = _string(raw['name']);
    final defaultFolder = _string(raw['defaultFolder']);
    final archived = _bool(raw['archived']);

    var next = board;
    if (name != null && name.isNotEmpty) {
      next = next.copyWith(name: name);
    }
    if (defaultFolder != null) {
      final metadata = Map<String, dynamic>.from(next.metadata);
      metadata['defaultFolder'] = defaultFolder;
      next = next.copyWith(metadata: metadata);
    }
    if (archived != null) {
      next = next.copyWith(archived: archived);
    }
    return next;
  }

  /// Computes a fitted viewport for `board.fit` without mutating any cubit.
  BoardViewport _fitViewport(
    BoardDocument board,
    Map<String, dynamic> raw,
  ) {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return board.viewport;

    final minX = panels.map((p) => p.bounds.x).reduce(math.min);
    final minY = panels.map((p) => p.bounds.y).reduce(math.min);
    final maxX = panels
        .map((p) => p.bounds.x + p.bounds.width)
        .reduce(math.max);
    final maxY = panels
        .map((p) => p.bounds.y + p.bounds.height)
        .reduce(math.max);

    final contentW = maxX - minX;
    final contentH = maxY - minY;
    const padding = 80.0;

    final vpW = _double(raw['viewportWidth']) ?? 1280.0;
    final vpH = _double(raw['viewportHeight']) ?? 800.0;
    final scaleX = (vpW - padding * 2) / contentW;
    final scaleY = (vpH - padding * 2) / contentH;
    final scale = math.min(scaleX, scaleY).clamp(0.1, 2.0);
    final tx = (vpW - contentW * scale) / 2 - minX * scale;
    final ty = (vpH - contentH * scale) / 2 - minY * scale;

    return board.viewport.copyWith(scale: scale, translation: Offset(tx, ty));
  }

  String? _resolvePanelId(dynamic value, Map<String, String> refs) {
    final id = _string(value);
    if (id == null) return null;
    return refs[id] ?? id;
  }

  String _nextId(String prefix) => '$prefix-${DateTime.now().microsecondsSinceEpoch}';

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  double? _double(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  bool? _bool(dynamic value) {
    if (value is bool) return value;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == 'yes' || lower == '1') return true;
      if (lower == 'false' || lower == 'no' || lower == '0') return false;
    }
    return null;
  }

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  Color? _color(dynamic value) => parseColor(_string(value));
}
