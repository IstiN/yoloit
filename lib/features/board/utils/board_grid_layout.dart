import 'dart:math' as math;

import 'package:yoloit/features/board/model/board_grid_mode.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Number of columns used when auto-arranging panels into a grid cloud.
const kGridAutoArrangeColumns = 8;

/// Grid position and span in cell coordinates.
class GridRect {
  const GridRect(this.col, this.row, {this.colSpan = 1, this.rowSpan = 1});

  final int col;
  final int row;
  final int colSpan;
  final int rowSpan;

  int get right => col + colSpan;
  int get bottom => row + rowSpan;

  bool overlaps(GridRect other) {
    return col < other.right &&
        right > other.col &&
        row < other.bottom &&
        bottom > other.row;
  }

  GridRect shifted(int dCol, int dRow) {
    return GridRect(col + dCol, row + dRow, colSpan: colSpan, rowSpan: rowSpan);
  }

  BoardPanelBounds toBounds(BoardGridMode mode) => gridRectToBounds(mode, this);

  @override
  String toString() => 'GridRect($col, $row, ${colSpan}x$rowSpan)';
}

/// Total pitch from one cell origin to the next.
double gridPitch(BoardGridMode mode) => mode.cellSize + mode.spacing;

/// Converts board-space bounds to the nearest grid rectangle.
GridRect boundsToGridRect(BoardGridMode mode, BoardPanelBounds bounds) {
  final pitch = gridPitch(mode);
  final col = (bounds.x / pitch).round();
  final row = (bounds.y / pitch).round();
  // Span is measured in pitch-sized steps so spacing between cells is included.
  final colSpan = math.max(1, ((bounds.width + mode.spacing) / pitch).round());
  final rowSpan = math.max(1, ((bounds.height + mode.spacing) / pitch).round());
  return GridRect(col, row, colSpan: colSpan, rowSpan: rowSpan);
}

/// Converts a grid rectangle back to board-space bounds.
BoardPanelBounds gridRectToBounds(BoardGridMode mode, GridRect rect) {
  final pitch = gridPitch(mode);
  return BoardPanelBounds(
    x: rect.col * pitch,
    y: rect.row * pitch,
    width: rect.colSpan * mode.cellSize + (rect.colSpan - 1) * mode.spacing,
    height: rect.rowSpan * mode.cellSize + (rect.rowSpan - 1) * mode.spacing,
  );
}

/// Builds a map of panel id to its grid rectangle.
Map<String, GridRect> buildGridRects(
  BoardGridMode mode,
  List<BoardPanelInstance> panels,
) {
  return {
    for (final panel in panels) panel.id: boundsToGridRect(mode, panel.bounds),
  };
}

/// Returns the ids of panels whose grid rect overlaps [rect], excluding
/// [excludeId] if provided.
List<String> findOverlappingPanels(
  GridRect rect,
  Map<String, GridRect> rects, {
  String? excludeId,
}) {
  final result = <String>[];
  for (final entry in rects.entries) {
    if (entry.key == excludeId) continue;
    if (entry.value.overlaps(rect)) {
      result.add(entry.key);
    }
  }
  return result;
}

/// Resolves overlaps by pushing [other] panels away from [target].
///
/// The push follows the smaller overlap axis (horizontal vs vertical). The
/// returned rectangles are integer-cell aligned.
GridRect _pushAway(GridRect target, GridRect other) {
  final overlapCols =
      (math.min(target.right, other.right) - math.max(target.col, other.col))
          .toInt();
  final overlapRows =
      (math.min(target.bottom, other.bottom) - math.max(target.row, other.row))
          .toInt();

  if (overlapCols <= 0 || overlapRows <= 0) return other;

  if (overlapCols <= overlapRows) {
    final direction = other.col >= target.col ? 1 : -1;
    return other.shifted(direction * overlapCols, 0);
  } else {
    final direction = other.row >= target.row ? 1 : -1;
    return other.shifted(0, direction * overlapRows);
  }
}

/// Moves [movedPanelId] to [targetRect] and recursively pushes any overlapping
/// panels just enough to resolve the overlap. Returns the updated panels in the
/// same order as the input.
List<BoardPanelInstance> pushPanelToRect(
  BoardGridMode mode,
  List<BoardPanelInstance> panels,
  String movedPanelId,
  GridRect targetRect,
) {
  final rects = buildGridRects(mode, panels);

  Map<String, GridRect> resolve(
    Map<String, GridRect> current,
    String panelId,
    GridRect target,
    Set<String> visited,
  ) {
    if (visited.contains(panelId)) return current;
    visited = {...visited, panelId};
    current = {...current, panelId: target};

    final overlapping = findOverlappingPanels(
      target,
      current,
      excludeId: panelId,
    );
    for (final otherId in overlapping) {
      final otherRect = current[otherId];
      if (otherRect == null) continue;
      final pushed = _pushAway(target, otherRect);
      current = resolve(current, otherId, pushed, visited);
    }
    return current;
  }

  final resolved = resolve(rects, movedPanelId, targetRect, <String>{});
  return panels.map((panel) {
    final newRect = resolved[panel.id];
    if (newRect == null || newRect == boundsToGridRect(mode, panel.bounds)) {
      return panel;
    }
    return panel.copyWith(bounds: gridRectToBounds(mode, newRect));
  }).toList();
}

Map<String, GridRect> _pushRecursive(
  Map<String, GridRect> rects,
  String panelId,
  int pushCol,
  int pushRow,
  Set<String> visited,
) {
  if (visited.contains(panelId)) return rects;
  visited = {...visited, panelId};

  final currentRect = rects[panelId];
  if (currentRect == null) return rects;

  final targetRect = currentRect.shifted(pushCol, pushRow);
  final dominantHorizontal = pushCol.abs() >= pushRow.abs();

  final overlapping = findOverlappingPanels(
    targetRect,
    rects,
    excludeId: panelId,
  );

  var current = rects;
  for (final otherId in overlapping) {
    final otherRect = current[otherId];
    if (otherRect == null) continue;

    final otherPushCol =
        dominantHorizontal ? pushCol.sign * targetRect.colSpan : 0;
    final otherPushRow =
        dominantHorizontal ? 0 : pushRow.sign * targetRect.rowSpan;

    current = _pushRecursive(
      current,
      otherId,
      otherPushCol,
      otherPushRow,
      visited,
    );
  }

  return {...current, panelId: targetRect};
}

/// Moves [movedPanelId] by ([deltaCol], [deltaRow]) in grid coordinates,
/// pushing any overlapping panels recursively in the dominant direction of the
/// move. Returns the updated panels in the same order as the input.
///
/// The dominant axis is horizontal when |deltaCol| >= |deltaRow|, otherwise
/// vertical. Each pushed panel is shifted by the mover's span on that axis,
/// which produces the watchOS-style "push neighbors" effect.
List<BoardPanelInstance> pushPanelInGrid(
  BoardGridMode mode,
  List<BoardPanelInstance> panels,
  String movedPanelId,
  int deltaCol,
  int deltaRow,
) {
  final rects = buildGridRects(mode, panels);
  final movedRect = rects[movedPanelId];
  if (movedRect == null) return panels;

  final pushedRects = _pushRecursive(
    rects,
    movedPanelId,
    deltaCol,
    deltaRow,
    <String>{},
  );

  return panels.map((panel) {
    final newRect = pushedRects[panel.id];
    if (newRect == null || newRect == boundsToGridRect(mode, panel.bounds)) {
      return panel;
    }
    return panel.copyWith(bounds: gridRectToBounds(mode, newRect));
  }).toList();
}

class _PackedRect {
  _PackedRect(this.index, this.rect);

  final int index;
  final GridRect rect;
}

class _Shelf {
  _Shelf({required this.y, required this.height});

  final int y;
  int height;
  int usedWidth = 0;
  final List<_PackedRect> items = [];
}

/// Packs a list of rectangles into a compact, roughly square area using a shelf
/// algorithm. Rectangles are sorted by descending height so that tall panels do
/// not create huge empty gaps in rows.
///
/// When [targetWidth] is provided it is used as the shelf width. Otherwise a
/// heuristic is computed from the total area and the largest rectangle.
///
/// The returned list is in the same order as the input [rects].
List<GridRect> _packRectsCompact(
  List<GridRect> rects, {
  int gap = 0,
  int? targetWidth,
}) {
  if (rects.isEmpty) return [];

  final maxWidth = rects.map((r) => r.colSpan).reduce(math.max);
  final effectiveTargetWidth =
      targetWidth ??
      math.max(
        maxWidth,
        math
            .sqrt(
              rects.fold<int>(
                0,
                (sum, rect) => sum + rect.colSpan * rect.rowSpan,
              ),
            )
            .ceil(),
      );

  final indexed = <(int, GridRect)>[
    for (var i = 0; i < rects.length; i++) (i, rects[i]),
  ];
  indexed.sort((a, b) {
    final heightCmp = b.$2.rowSpan.compareTo(a.$2.rowSpan);
    if (heightCmp != 0) return heightCmp;
    final widthCmp = b.$2.colSpan.compareTo(a.$2.colSpan);
    if (widthCmp != 0) return widthCmp;
    return a.$1.compareTo(b.$1);
  });

  final shelves = <_Shelf>[];

  for (final (index, rect) in indexed) {
    var placed = false;
    for (final shelf in shelves) {
      if (rect.rowSpan <= shelf.height &&
          shelf.usedWidth + (shelf.items.isNotEmpty ? gap : 0) + rect.colSpan <=
              effectiveTargetWidth) {
        final x = shelf.usedWidth + (shelf.items.isNotEmpty ? gap : 0);
        shelf.items.add(
          _PackedRect(
            index,
            GridRect(x, shelf.y, colSpan: rect.colSpan, rowSpan: rect.rowSpan),
          ),
        );
        shelf.usedWidth = x + rect.colSpan;
        placed = true;
        break;
      }
    }

    if (!placed) {
      final y =
          shelves.isEmpty ? 0 : shelves.last.y + shelves.last.height + gap;
      final shelf = _Shelf(y: y, height: rect.rowSpan);
      shelf.items.add(
        _PackedRect(
          index,
          GridRect(0, y, colSpan: rect.colSpan, rowSpan: rect.rowSpan),
        ),
      );
      shelf.usedWidth = rect.colSpan;
      shelves.add(shelf);
    }
  }

  final result = List<GridRect?>.filled(rects.length, null);
  for (final shelf in shelves) {
    for (final item in shelf.items) {
      result[item.index] = item.rect;
    }
  }
  return result.cast<GridRect>();
}

/// Arranges visible panels in a compact cloud.
///
/// Tall panels are packed together so the overall shape stays roughly square
/// instead of stretching into a long vertical strip. Hidden panels are kept at
/// their current position.
List<BoardPanelInstance> arrangePanelsInCloud(
  BoardGridMode mode,
  List<BoardPanelInstance> panels, {
  int maxColumns = kGridAutoArrangeColumns,
}) {
  final visible = panels.where((p) => !p.hidden).toList();
  final hidden = panels.where((p) => p.hidden).toList();

  final rects = visible.map((p) => boundsToGridRect(mode, p.bounds)).toList();
  final packed = _packRectsCompact(rects, gap: 0);

  final result = <BoardPanelInstance>[];
  for (var i = 0; i < visible.length; i++) {
    result.add(visible[i].copyWith(bounds: gridRectToBounds(mode, packed[i])));
  }

  return [...result, ...hidden];
}

int _typePriority(String type) {
  final lower = type.toLowerCase();
  if (lower.contains('terminal')) return 0;
  if (lower.contains('chat')) return 1;
  if (lower.contains('app')) return 2;
  if (lower.contains('note')) return 3;
  return 4;
}

/// Arranges panels in a compact grid grouped by type.
///
/// Panels of the same type are packed into a small, roughly square cloud,
/// and those type clouds are laid out in a larger compact cloud. This keeps
/// related panels close together without creating tall, sparse columns.
///
/// Hidden panels are kept at their current position.
List<BoardPanelInstance> arrangePanelsByType(
  BoardGridMode mode,
  List<BoardPanelInstance> panels, {
  int groupGap = 1,
}) {
  final hidden = panels.where((p) => p.hidden).toList();
  final visible = panels.where((p) => !p.hidden).toList();

  final groups = <String, List<BoardPanelInstance>>{};
  for (final panel in visible) {
    groups.putIfAbsent(panel.type, () => []).add(panel);
  }

  for (final group in groups.values) {
    group.sort((a, b) => a.title.compareTo(b.title));
  }

  final sortedKeys =
      groups.keys.toList()..sort((a, b) {
        final priorityCmp = _typePriority(a).compareTo(_typePriority(b));
        if (priorityCmp != 0) return priorityCmp;
        return a.compareTo(b);
      });

  // Pack each type group into its own small (roughly square) cloud.
  final groupBlocks = <String, List<BoardPanelInstance>>{};
  final groupBounds = <String, GridRect>{};
  for (final type in sortedKeys) {
    final groupPanels = groups[type]!;
    final rects =
        groupPanels.map((p) => boundsToGridRect(mode, p.bounds)).toList();
    final packed = _packRectsCompact(rects, gap: 0);

    final arranged = <BoardPanelInstance>[];
    var maxCol = 0;
    var maxRow = 0;
    for (var i = 0; i < groupPanels.length; i++) {
      final rect = packed[i];
      arranged.add(
        groupPanels[i].copyWith(bounds: gridRectToBounds(mode, rect)),
      );
      if (rect.right > maxCol) maxCol = rect.right;
      if (rect.bottom > maxRow) maxRow = rect.bottom;
    }

    groupBlocks[type] = arranged;
    // Add a one-cell padding to the block so neighbouring groups stay separated.
    groupBounds[type] = GridRect(
      0,
      0,
      colSpan: math.max(1, maxCol + groupGap),
      rowSpan: math.max(1, maxRow + groupGap),
    );
  }

  // Lay the type clouds out in a larger compact cloud.
  final groupRects = sortedKeys.map((k) => groupBounds[k]!).toList();
  final groupCount = sortedKeys.length;
  final groupsPerRow = math.max(1, math.sqrt(groupCount).ceil());
  final maxGroupWidth = groupRects.map((r) => r.colSpan).reduce(math.max);
  final packedGroups = _packRectsCompact(
    groupRects,
    gap: 0,
    targetWidth: maxGroupWidth * groupsPerRow,
  );

  final result = <BoardPanelInstance>[];
  for (var groupIndex = 0; groupIndex < sortedKeys.length; groupIndex++) {
    final type = sortedKeys[groupIndex];
    final base = packedGroups[groupIndex];
    final block = groupBlocks[type]!;

    for (final panel in block) {
      final rect = boundsToGridRect(mode, panel.bounds);
      final placed = GridRect(
        base.col + rect.col,
        base.row + rect.row,
        colSpan: rect.colSpan,
        rowSpan: rect.rowSpan,
      );
      result.add(panel.copyWith(bounds: gridRectToBounds(mode, placed)));
    }
  }

  return [...result, ...hidden];
}

/// Snaps an existing panel's bounds to the nearest grid cell, preserving its
/// current span.
BoardPanelInstance snapPanelToGrid(
  BoardGridMode mode,
  BoardPanelInstance panel,
) {
  final rect = boundsToGridRect(mode, panel.bounds);
  return panel.copyWith(bounds: gridRectToBounds(mode, rect));
}

/// Computes the grid rectangle for a resize operation that adds
/// [deltaCols]/[deltaRows] to the panel's current span while keeping its top-left
/// cell fixed.
GridRect resizeGridRect(
  BoardGridMode mode,
  BoardPanelBounds bounds, {
  required int deltaCols,
  required int deltaRows,
}) {
  final rect = boundsToGridRect(mode, bounds);
  return GridRect(
    rect.col,
    rect.row,
    colSpan: math.max(1, rect.colSpan + deltaCols),
    rowSpan: math.max(1, rect.rowSpan + deltaRows),
  );
}

/// Returns the board-space bounds for a panel resized by whole grid cells from
/// its current bounds.
BoardPanelBounds resizeBoundsInGrid(
  BoardGridMode mode,
  BoardPanelBounds bounds, {
  required int deltaCols,
  required int deltaRows,
}) {
  return gridRectToBounds(
    mode,
    resizeGridRect(mode, bounds, deltaCols: deltaCols, deltaRows: deltaRows),
  );
}
