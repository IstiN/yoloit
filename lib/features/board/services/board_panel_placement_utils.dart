import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';

/// Adjusts a plugin's default [initialState] so that new panels created on
/// [board] inherit the board's default folder when appropriate.
Map<String, dynamic> initialPanelStateForBoard(
  Map<String, dynamic> initialState,
  String typeId,
  BoardDocument board,
) {
  final defaultFolder = board.defaultFolder;
  if (defaultFolder.isEmpty) return initialState;
  if (typeId == kFileTreePluginTypeId) {
    return {...initialState, 'rootPath': defaultFolder};
  }
  if (typeId == kChatPluginTypeId) {
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
  if (typeId == kTerminalPluginTypeId) {
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

/// Computes the axis-aligned bounding box of the given [panels].
({double minX, double minY, double maxX, double maxY}) boundingBoxOfPanels(
  List<BoardPanelInstance> panels,
) {
  final minX = panels.map((p) => p.bounds.x).reduce((a, b) => a < b ? a : b);
  final minY = panels.map((p) => p.bounds.y).reduce((a, b) => a < b ? a : b);
  final maxX = panels
      .map((p) => p.bounds.x + p.bounds.width)
      .reduce((a, b) => a > b ? a : b);
  final maxY = panels
      .map((p) => p.bounds.y + p.bounds.height)
      .reduce((a, b) => a > b ? a : b);
  return (minX: minX, minY: minY, maxX: maxX, maxY: maxY);
}

/// Returns a viewport that fits all visible panels (or [panels]) into a
/// rectangle of the given size with a small padding margin.
BoardViewport fitBoardViewport(
  BoardDocument board, {
  required double viewportWidth,
  required double viewportHeight,
  List<BoardPanelInstance>? panels,
}) {
  final visible = panels ?? board.panels.where((p) => !p.hidden).toList();
  if (visible.isEmpty) return board.viewport;

  final bounds = boundingBoxOfPanels(visible);
  final contentW = bounds.maxX - bounds.minX;
  final contentH = bounds.maxY - bounds.minY;
  const padding = 80.0;

  final scaleX = (viewportWidth - padding * 2) / contentW;
  final scaleY = (viewportHeight - padding * 2) / contentH;
  final scale = (scaleX < scaleY ? scaleX : scaleY).clamp(0.1, 2.0);
  final tx = (viewportWidth - contentW * scale) / 2 - bounds.minX * scale;
  final ty = (viewportHeight - contentH * scale) / 2 - bounds.minY * scale;

  return board.viewport.copyWith(
    scale: scale,
    translation: Offset(tx, ty),
  );
}

/// Finds a non-overlapping position for a new panel on a free-form board.
///
/// Callers that support grid mode should branch to their grid placement logic
/// before falling back to this helper.
BoardPanelBounds nextAvailableFreeformBounds(
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

/// Builds a [BoardPanelInstance] from a raw operation map.
///
/// Returns `null` when the requested type is missing or unknown. The caller is
/// responsible for adding the panel to the board and tracking any YAML refs.
BoardPanelInstance? buildPanelFromRaw(
  Map<String, dynamic> raw,
  BoardDocument board, {
  required String Function() nextId,
  required Color? Function(dynamic value) colorParser,
  Map<String, dynamic> Function(Map<String, dynamic> state)? resolveState,
}) {
  final typeId = raw['type']?.toString() ?? raw['typeId']?.toString();
  if (typeId == null || typeId.isEmpty) return null;

  final plugin = BoardPluginRegistry.instance.pluginFor(typeId);
  if (plugin == null) return null;

  final title = raw['title']?.toString() ?? plugin.displayName;
  final x = (raw['x'] as num?)?.toDouble() ?? 100.0;
  final y = (raw['y'] as num?)?.toDouble() ?? 100.0;
  final width =
      (raw['width'] as num?)?.toDouble() ?? plugin.defaultSize.width;
  final height =
      (raw['height'] as num?)?.toDouble() ?? plugin.defaultSize.height;
  final rawState =
      raw['state'] is Map
          ? Map<String, dynamic>.from(raw['state'] as Map)
          : null;
  final params =
      raw['params'] is Map
          ? Map<String, dynamic>.from(raw['params'] as Map)
          : null;
  final ref = raw['ref']?.toString();
  final color = colorParser(raw['color']);
  final hidden = _boolFromRaw(raw['hidden']);
  final locked = _boolFromRaw(raw['locked']);
  final pinned = _boolFromRaw(raw['pinned']);
  final panelId =
      raw['id']?.toString() ?? raw['panelId']?.toString() ?? nextId();
  final zIndex = (raw['zIndex'] as num?)?.toInt() ?? _nextZIndexForBoard(board);

  final resolved = rawState;
  final state = <String, dynamic>{
    ...plugin.initialState,
    if (resolved != null)
      ...(resolveState != null ? resolveState(resolved) : resolved),
  };

  return BoardPanelInstance(
    id: panelId,
    type: typeId,
    title: title.trim().isEmpty ? plugin.displayName : title.trim(),
    bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
    color: color,
    params: {...?params, if (ref != null && ref.isNotEmpty) 'yamlRef': ref},
    state: state,
    zIndex: zIndex,
    hidden: hidden,
    locked: locked,
    pinned: pinned,
  );
}

bool _boolFromRaw(dynamic value) {
  if (value is bool) return value;
  return value?.toString().toLowerCase() == 'true';
}

int _nextZIndexForBoard(BoardDocument board) =>
    board.panels.fold<int>(
          0,
          (value, panel) => panel.zIndex > value ? panel.zIndex : value,
        ) +
        1;
