import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/file_preview_plugin_base.dart';

/// Result of a placement computation.
class PanelPlacement {
  const PanelPlacement({
    required this.bounds,
    required this.zIndex,
  });

  final BoardPanelBounds bounds;
  final int zIndex;
}

/// Helpers for intelligently placing panels on a board without overlap.
class PanelPlacementHelper {
  PanelPlacementHelper._();

  // ── Deduplication ──────────────────────────────────────────────────────────

  /// Finds an existing [FilePreviewPlugin] panel that already shows [filePath].
  static BoardPanelInstance? findExistingFilePreview(
    BoardDocument board,
    String filePath,
  ) {
    for (final panel in board.panels) {
      if (panel.type != FilePreviewPluginBase.kTypeId) continue;
      if (panel.state['path'] == filePath) return panel;
    }
    return null;
  }

  // ── Desired size by file type ──────────────────────────────────────────────

  /// Returns a comfortable default size for a file-preview panel based on the
  /// file extension and content type.
  static Size desiredSizeForFile(String filePath) {
    final ext =
        filePath.contains('.')
            ? filePath.split('.').last.toLowerCase()
            : '';

    if (_isImageExt(ext) || _isSvgExt(ext)) {
      // Square-ish for images; actual image will letter-box inside.
      return const Size(560, 520);
    }
    if (_isVideoExt(ext)) {
      return const Size(800, 460); // 16:9-ish
    }
    if (_isAudioExt(ext)) {
      return const Size(460, 340); // compact player
    }
    if (_isPdfExt(ext)) {
      return const Size(520, 720); // A4 portrait feel
    }
    if (_isMarkdownExt(ext)) {
      return const Size(640, 560);
    }
    // Text / code / unknown → desktop browser-like landscape
    return const Size(780, 540);
  }

  // ── Placement engine ───────────────────────────────────────────────────────

  /// Finds a non-overlapping position and returns the bounds + next z-index.
  ///
  /// The search prioritises:
  /// 1. Positions around the [anchorPanelId] (or focused / top-z panel).
  /// 2. Positions around [viewportCenter] — the centre of what the user is
  ///    currently looking at. This prevents jumping far away when the focused
  ///    panel is off-screen.
  /// 3. A cascading grid sweeping outward from the viewport centre.
  /// 4. Fallback to the far right of the right-most panel.
  static PanelPlacement findPlacement(
    BoardDocument board, {
    required Size desiredSize,
    String? anchorPanelId,
    Offset? viewportCenter,
    double gap = 48.0,
  }) {
    final anchor = _resolveAnchor(board, anchorPanelId);
    final existingRects = board.panels.map((p) => p.bounds.rect).toList();

    // 1. Try positions around the anchor panel (right, bottom, left, top, diagonals).
    final aroundAnchor = _positionsAroundPanel(anchor, desiredSize, gap: gap);
    for (final candidate in aroundAnchor) {
      if (!_overlapsAny(candidate.rect, existingRects, gap: gap)) {
        return PanelPlacement(
          bounds: candidate,
          zIndex: _nextZIndex(board),
        );
      }
    }

    // 2. Try positions around the viewport centre — this is where the user is
    //    actually looking right now, so placing here avoids a jarring jump.
    final effectiveViewport = viewportCenter ?? _fallbackCenter(anchor);
    final aroundViewport = _positionsAroundPoint(
      effectiveViewport,
      desiredSize,
      gap: gap,
    );
    for (final candidate in aroundViewport) {
      if (!_overlapsAny(candidate.rect, existingRects, gap: gap)) {
        return PanelPlacement(
          bounds: candidate,
          zIndex: _nextZIndex(board),
        );
      }
    }

    // 3. Cascading grid from the viewport centre with the *desired* panel size
    //    as the step (not the anchor size, which may be very different).
    final grid = _cascadingGridFromPoint(
      effectiveViewport,
      desiredSize,
      gap: gap,
    );
    for (final candidate in grid) {
      if (!_overlapsAny(candidate.rect, existingRects, gap: gap)) {
        return PanelPlacement(
          bounds: candidate,
          zIndex: _nextZIndex(board),
        );
      }
    }

    // 4. Fallback: place far to the right of the right-most panel.
    final rightmostX = existingRects.isEmpty
        ? 0.0
        : existingRects.map((r) => r.right).reduce(math.max);
    return PanelPlacement(
      bounds: BoardPanelBounds(
        x: rightmostX + gap,
        y: effectiveViewport.dy,
        width: desiredSize.width,
        height: desiredSize.height,
      ),
      zIndex: _nextZIndex(board),
    );
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  static BoardPanelInstance? _resolveAnchor(
    BoardDocument board,
    String? preferredId,
  ) {
    if (preferredId != null) {
      for (final p in board.panels) {
        if (p.id == preferredId) return p;
      }
    }

    final focusedId = board.viewport.focusedPanelId;
    if (focusedId != null) {
      for (final p in board.panels) {
        if (p.id == focusedId) return p;
      }
    }

    if (board.panels.isNotEmpty) {
      var top = board.panels.first;
      for (final p in board.panels) {
        if (p.zIndex > top.zIndex) top = p;
      }
      return top;
    }

    return null;
  }

  static Offset _fallbackCenter(BoardPanelInstance? anchor) {
    return Offset(
      (anchor?.bounds.x ?? 200) + (anchor?.bounds.width ?? 0) / 2,
      (anchor?.bounds.y ?? 200) + (anchor?.bounds.height ?? 0) / 2,
    );
  }

  static int _nextZIndex(BoardDocument board) {
    if (board.panels.isEmpty) return 1;
    return board.panels.map((p) => p.zIndex).reduce(math.max) + 1;
  }

  /// Generates candidate positions around an existing panel:
  /// right → bottom → left → top → bottom-right → bottom-left → top-right → top-left.
  static List<BoardPanelBounds> _positionsAroundPanel(
    BoardPanelInstance? anchor,
    Size size, {
    double gap = 48.0,
  }) {
    final originX = anchor?.bounds.x ?? 200;
    final originY = anchor?.bounds.y ?? 200;
    final originW = anchor?.bounds.width ?? 0;
    final originH = anchor?.bounds.height ?? 0;

    return _positionsAroundPoint(
      Offset(originX + originW / 2, originY + originH / 2),
      size,
      gap: gap,
      refWidth: originW,
      refHeight: originH,
    );
  }

  /// Generates candidate positions radiating from a board-space point.
  /// When [refWidth] / [refHeight] are supplied the offsets are sized to butt
  /// up against a reference rectangle; otherwise they use the candidate [size].
  static List<BoardPanelBounds> _positionsAroundPoint(
    Offset centre,
    Size size, {
    double gap = 48.0,
    double refWidth = 0,
    double refHeight = 0,
  }) {
    final halfW = size.width / 2;
    final halfH = size.height / 2;
    final halfRefW = refWidth / 2;
    final halfRefH = refHeight / 2;

    // horizontal / vertical offsets from the reference edge (or candidate size if no ref)
    final dx = halfRefW > 0 ? halfRefW + gap + halfW : halfW + gap;
    final dy = halfRefH > 0 ? halfRefH + gap + halfH : halfH + gap;

    return [
      // Same row / column
      BoardPanelBounds(
        x: centre.dx + dx - halfW,
        y: centre.dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx - halfW,
        y: centre.dy + dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx - dx - halfW,
        y: centre.dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx - halfW,
        y: centre.dy - dy - halfH,
        width: size.width,
        height: size.height,
      ),
      // Diagonals
      BoardPanelBounds(
        x: centre.dx + dx - halfW,
        y: centre.dy + dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx - dx - halfW,
        y: centre.dy + dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx + dx - halfW,
        y: centre.dy - dy - halfH,
        width: size.width,
        height: size.height,
      ),
      BoardPanelBounds(
        x: centre.dx - dx - halfW,
        y: centre.dy - dy - halfH,
        width: size.width,
        height: size.height,
      ),
    ];
  }

  /// Generates a cascading grid sweeping outward from [centre] in reading order
  /// (right then down). The step is based on the *desired* panel size so small
  /// gaps are not skipped when the anchor panel is huge.
  static List<BoardPanelBounds> _cascadingGridFromPoint(
    Offset centre,
    Size size, {
    double gap = 48.0,
    int maxCols = 5,
    int maxRows = 5,
  }) {
    final candidates = <BoardPanelBounds>[];
    final stepX = size.width + gap;
    final stepY = size.height + gap;

    for (var row = -maxRows; row <= maxRows; row++) {
      for (var col = -maxCols; col <= maxCols; col++) {
        if (row == 0 && col == 0) continue;
        candidates.add(
          BoardPanelBounds(
            x: centre.dx + col * stepX - size.width / 2,
            y: centre.dy + row * stepY - size.height / 2,
            width: size.width,
            height: size.height,
          ),
        );
      }
    }
    return candidates;
  }

  static bool _overlapsAny(
    Rect candidate,
    List<Rect> existing, {
    double gap = 48.0,
  }) {
    final padded = candidate.inflate(gap / 2);
    for (final other in existing) {
      if (padded.overlaps(other.inflate(gap / 2))) return true;
    }
    return false;
  }

  // ── File-type helpers ──────────────────────────────────────────────────────

  static bool _isImageExt(String ext) {
    return const {
      'png',
      'jpg',
      'jpeg',
      'gif',
      'bmp',
      'webp',
    }.contains(ext);
  }

  static bool _isSvgExt(String ext) => ext == 'svg';

  static bool _isPdfExt(String ext) => ext == 'pdf';

  static bool _isVideoExt(String ext) {
    return const {
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      'm4v',
      'wmv',
      'flv',
    }.contains(ext);
  }

  static bool _isAudioExt(String ext) {
    return const {
      'mp3',
      'aac',
      'wav',
      'ogg',
      'flac',
      'm4a',
      'opus',
      'wma',
    }.contains(ext);
  }

  static bool _isMarkdownExt(String ext) =>
      const {'md', 'markdown'}.contains(ext);
}
