import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/utils/panel_placement.dart';

void main() {
  BoardPanelInstance panel(
    String id,
    double x,
    double y,
    double w,
    double h, {
    int zIndex = 0,
  }) {
    return BoardPanelInstance(
      id: id,
      type: 'board.note.markdown',
      title: id,
      bounds: BoardPanelBounds(x: x, y: y, width: w, height: h),
      zIndex: zIndex,
    );
  }

  bool overlapsExisting(BoardPanelBounds bounds, BoardDocument board) {
    final rect = bounds.rect;
    return board.panels.any((p) => rect.overlaps(p.bounds.rect));
  }

  group('PanelPlacementHelper.findPlacement — anchor resolution', () {
    test('empty board uses the default origin and z-index 1', () {
      const board = BoardDocument(id: 'b1', name: 'Board');

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'missing',
      );

      // Default origin (200, 200), candidate to the right of it.
      expect(placement.bounds.x, 248);
      expect(placement.bounds.y, 150);
      expect(placement.bounds.width, 100);
      expect(placement.bounds.height, 100);
      expect(placement.zIndex, 1);
    });

    test('explicit anchorPanelId wins over viewport centre and focus', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        viewport: const BoardViewport(focusedPanelId: 'b'),
        panels: [
          panel('a', 100, 100, 200, 100, zIndex: 1),
          panel('b', 1000, 1000, 100, 100, zIndex: 5),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'a',
        viewportCenter: const Offset(5000, 5000),
      );

      // Right of panel a: centre (200, 150), dx = 100 + 48 + 50 = 198.
      expect(placement.bounds.x, 348);
      expect(placement.bounds.y, 100);
      expect(placement.zIndex, 6);
      expect(overlapsExisting(placement.bounds, board), isFalse);
    });

    test('unknown anchorPanelId falls back to the focused panel', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        viewport: const BoardViewport(focusedPanelId: 'b'),
        panels: [
          panel('a', 100, 100, 200, 100, zIndex: 1),
          panel('b', 1000, 1000, 100, 100, zIndex: 5),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'missing',
      );

      // Right of panel b: centre (1050, 1050), dx = 50 + 48 + 50 = 148.
      expect(placement.bounds.x, 1148);
      expect(placement.bounds.y, 1000);
      expect(placement.zIndex, 6);
    });

    test('unknown focus falls back to the top-z panel', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        viewport: const BoardViewport(focusedPanelId: 'ghost'),
        panels: [
          panel('low', 0, 0, 100, 100, zIndex: 1),
          panel('top', 500, 0, 100, 100, zIndex: 9),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
      );

      // Right of the z-9 panel: centre (550, 50), dx = 148.
      expect(placement.bounds.x, 648);
      expect(placement.bounds.y, 0);
      expect(placement.zIndex, 10);
      expect(overlapsExisting(placement.bounds, board), isFalse);
    });
  });

  group('PanelPlacementHelper.findPlacement — search stages', () {
    test('blocked anchor positions fall through to the viewport centre', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [
          panel('anchor', 100, 100, 50, 50, zIndex: 1),
          // Huge blocker swallowing every position around the anchor.
          panel('blocker', -1000, -1000, 3000, 3000, zIndex: 2),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'anchor',
        viewportCenter: const Offset(5000, 5000),
      );

      // Right of the viewport centre, dx = 50 + 48 = 98.
      expect(placement.bounds.x, 5048);
      expect(placement.bounds.y, 4950);
      expect(placement.zIndex, 3);
      expect(overlapsExisting(placement.bounds, board), isFalse);
    });

    test('blocked anchor and viewport positions use the cascading grid', () {
      // Anchor at (100, 100, 50x50) → centre (125, 125), dx = dy = 123.
      // The eight blockers cover the around-anchor candidates (each is the
      // candidate rect shifted 25 down, still overlapping after inflation).
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [
          panel('anchor', 100, 100, 50, 50, zIndex: 1),
          panel('r', 198, 100, 100, 100, zIndex: 2),
          panel('b', 75, 223, 100, 100, zIndex: 3),
          panel('l', -48, 100, 100, 100, zIndex: 4),
          panel('t', 75, -23, 100, 100, zIndex: 5),
          panel('br', 198, 223, 100, 100, zIndex: 6),
          panel('bl', -48, 223, 100, 100, zIndex: 7),
          panel('tr', 198, -23, 100, 100, zIndex: 8),
          panel('tl', -48, -23, 100, 100, zIndex: 9),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'anchor',
      );

      // Grid step = 148; first free cell is row -5, col -5 from (125, 125).
      expect(placement.bounds.x, -665);
      expect(placement.bounds.y, -665);
      expect(placement.zIndex, 10);
      expect(overlapsExisting(placement.bounds, board), isFalse);
    });

    test('everything blocked falls back to the right of the board', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [
          panel('anchor', 0, 0, 100, 100, zIndex: 3),
          // Giant blocker strictly covering every candidate position,
          // including the whole cascading grid sweep.
          panel('blocker', -2000, -2000, 4000, 4000, zIndex: 1),
        ],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        anchorPanelId: 'anchor',
        viewportCenter: const Offset(500, 500),
      );

      // Right-most edge (blocker right = 2000) + gap, aligned with the
      // viewport centre vertically.
      expect(placement.bounds.x, 2048);
      expect(placement.bounds.y, 500);
      expect(placement.bounds.width, 100);
      expect(placement.bounds.height, 100);
      expect(placement.zIndex, 4);
    });

    test('respects a custom gap when placing next to the anchor', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [panel('anchor', 0, 0, 100, 100, zIndex: 0)],
      );

      final placement = PanelPlacementHelper.findPlacement(
        board,
        desiredSize: const Size(100, 100),
        gap: 10,
      );

      // dx = 50 + 10 + 50 = 110 from centre (50, 50).
      expect(placement.bounds.x, 110);
      expect(placement.bounds.y, 0);
      expect(placement.zIndex, 1);
      expect(overlapsExisting(placement.bounds, board), isFalse);
    });
  });
}
