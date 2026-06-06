import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/features/mindmap/model/mindmap_node_model.dart';

/// Column x-offsets for each column index.
/// Column 1 (Sessions) is wide enough for the merged session+terminal card.
/// All columns are offset by 2000 so users have room to pan left freely.
const _columnX = [
  2040.0,  // 0 Workspaces
  2260.0,  // 1 Sessions (merged with terminal) — wide card
  2680.0,  // 2 Repositories
  2900.0,  // 3 Branches
  3100.0,  // 4 Files Changed
  3360.0,  // 5 Editor
  3860.0,  // 6 Runs (attached from session)
  4240.0,  // 7 File Tree (file browser only)
  4580.0,  // 8 Diff / Git Changes
];

const _columnMargin = 20.0;
const _nodeVMargin  = 20.0;
const _nodeHMargin  = 24.0;
const _canvasStartY = 2000.0; // large offset so users can pan upward freely

/// Per-column override for vertical node spacing. Workspaces use a larger
/// margin so the list breathes.
const _columnVMargin = <int, double>{
  0: 44.0, // Workspaces — more breathing room
};

/// Computes collision-free positions for nodes.
///
/// NEW: when [connections] are provided and a node appears for the first time
/// (not in [existing]), its initial position is placed *near its connection
/// source* instead of the default column x.  This makes new panels "pop up"
/// next to the card that triggered them.
class MindMapLayoutEngine {
  MindMapLayoutEngine();

  /// Compute positions for [nodes].
  /// [existing] provides previously saved/user-dragged positions (preserved).
  /// [connections] are used to find source-hint positions for new nodes.
  /// Returns a new map with all node ids mapped to their assigned Offset.
  Map<String, Offset> compute({
    required List<MindMapNodeData> nodes,
    required Map<String, Offset> existing,
    required Map<String, Size> sizes,
    Set<String> locked = const {},
    List<MindMapConnection> connections = const [],
  }) {
    final result = <String, Offset>{};

    // All placed rects (for global overlap/push detection).
    final allRects = <String, Rect>{};   // id → rect

    // Group already-placed rects per column for per-column free-Y search.
    final columnRects = <int, List<Rect>>{};

    // Build source-hint map from connections: toId → from-node position hint.
    // Used when the toId node has no existing position yet.
    final Map<String, String> toFromId = {
      for (final c in connections) c.toId: c.fromId,
    };

    // ── Pass 1: seed with already-positioned nodes (locked first) ────────────
    void seedNode(MindMapNodeData node) {
      if (!existing.containsKey(node.id)) return;
      final pos  = existing[node.id]!;
      final size = sizes[node.id] ?? node.defaultSize;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      result[node.id] = pos;
      allRects[node.id] = rect;
      columnRects.putIfAbsent(node.columnIndex, () => [])
          .add(rect);
    }

    for (final n in nodes) {
      if (locked.contains(n.id)) seedNode(n);
    }
    for (final n in nodes) {
      if (!locked.contains(n.id)) seedNode(n);
    }

    // ── Pass 2: place new nodes ───────────────────────────────────────────────
    for (final node in nodes) {
      if (result.containsKey(node.id)) continue; // already positioned above

      final size    = sizes[node.id] ?? node.defaultSize;
      final colIdx  = node.columnIndex;
      final vMargin = _columnVMargin[colIdx] ?? _nodeVMargin;

      // Try to find the source node's position as a placement hint.
      final sourceId  = toFromId[node.id];
      final sourcePos = sourceId != null ? result[sourceId] : null;
      final sourceSize = sourceId != null
          ? (sizes[sourceId] ?? nodes.firstWhere(
              (n) => n.id == sourceId,
              orElse: () => node).defaultSize)
          : null;

      Offset pos;

      if (sourcePos != null && sourceSize != null) {
        // Place to the RIGHT of the source node, near its vertical center.
        final hintX = sourcePos.dx + sourceSize.width + _nodeHMargin;
        final hintY = sourcePos.dy;
        pos = _findFreeNear(hintX, hintY, size, allRects, vMargin);
      } else {
        // Fall back to column-based placement.
        final x = colIdx < _columnX.length
            ? _columnX[colIdx]
            : _columnX.last + _columnMargin;
        final occupied = columnRects[colIdx] ?? [];
        pos = Offset(x, _findFreeY(x, size, occupied, vMargin));
      }

      result[node.id] = pos;
      final rect = Rect.fromLTWH(pos.dx, pos.dy, size.width, size.height);
      allRects[node.id] = rect;
      columnRects.putIfAbsent(colIdx, () => []).add(rect);

      // ── Push overlapping UNLOCKED neighbours out of the way ──────────────
      _pushOverlapping(node.id, rect, result, allRects, locked, nodes, sizes,
          vMargin);
    }

    return result;
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Find a free slot near (hintX, hintY), searching outward in concentric
  /// rings so the new node lands as close to the hint as possible.
  Offset _findFreeNear(
    double hintX,
    double hintY,
    Size size,
    Map<String, Rect> allRects,
    double margin,
  ) {
    // Try the hint directly, then spiral outward in steps.
    const step = 40.0;
    const maxRings = 20;

    for (int ring = 0; ring <= maxRings; ring++) {
      final offsets = ring == 0
          ? [const Offset(0, 0)]
          : _ringOffsets(ring, step);
      for (final off in offsets) {
        final x = hintX + off.dx;
        final y = hintY + off.dy;
        final rect = Rect.fromLTWH(x, y, size.width, size.height);
        final blocked = allRects.values
            .any((r) => r.inflate(margin / 2).overlaps(rect));
        if (!blocked) return Offset(x, y);
      }
    }
    // Fallback: just place at hint (extremely unlikely to get here).
    return Offset(hintX, hintY);
  }

  /// Candidate offsets for a given search ring.
  static List<Offset> _ringOffsets(int ring, double step) {
    // Prefer horizontal axis (place to the right first) then top/bottom.
    final r = ring * step;
    return [
      Offset(0, -r),  Offset(0, r),
      Offset(r, 0),   Offset(-r, 0),
      Offset(r, -r),  Offset(r, r),
      Offset(-r, -r), Offset(-r, r),
    ];
  }

  /// Nudge any unlocked nodes that overlap [rect] away from it.
  void _pushOverlapping(
    String newId,
    Rect rect,
    Map<String, Offset> result,
    Map<String, Rect> allRects,
    Set<String> locked,
    List<MindMapNodeData> nodes,
    Map<String, Size> sizes,
    double margin,
  ) {
    for (final otherId in allRects.keys.toList()) {
      if (otherId == newId) continue;
      if (locked.contains(otherId)) continue;
      final otherRect = allRects[otherId]!;
      if (!rect.inflate(margin).overlaps(otherRect)) continue;

      // Push the overlapping node downward.
      final pushY = rect.bottom + margin;
      final newPos = Offset(otherRect.left, pushY);
      result[otherId] = newPos;
      final node = nodes.firstWhere((n) => n.id == otherId,
          orElse: () => nodes.first);
      final size = sizes[otherId] ?? node.defaultSize;
      allRects[otherId] =
          Rect.fromLTWH(newPos.dx, newPos.dy, size.width, size.height);
    }
  }

  double _findFreeY(double x, Size size, List<Rect> occupied, double vMargin) {
    double candidate = _canvasStartY;
    bool fits = false;

    while (!fits) {
      final rect = Rect.fromLTWH(x, candidate, size.width, size.height);
      var maxBottom = candidate;
      var collision = false;
      for (final r in occupied) {
        if (r.inflate(vMargin).overlaps(rect)) {
          collision = true;
          if (r.bottom > maxBottom) maxBottom = r.bottom;
        }
      }
      if (!collision) {
        fits = true;
      } else {
        candidate = maxBottom + vMargin;
      }
    }
    return candidate;
  }

  /// X center of a column — used for drawing column labels.
  static double columnLabelX(int colIdx) =>
      colIdx < _columnX.length ? _columnX[colIdx] : _columnX.last;

  static const columnLabels = [
    'WORKSPACES',
    'SESSIONS / TERMINALS',
    'REPOSITORIES',
    'BRANCHES',
    'FILES CHANGED',
    'EDITOR',
    'RUNS',
    'FILE TREE',
    'DIFF / GIT CHANGES',
  ];
}

