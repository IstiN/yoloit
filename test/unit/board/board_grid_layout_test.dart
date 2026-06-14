import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_grid_mode.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/utils/board_grid_layout.dart';

void main() {
  const mode = BoardGridMode(cellSize: 220.0, spacing: 24.0);
  final pitch = gridPitch(mode);

  BoardPanelInstance makePanel(
    String id,
    String type,
    double x,
    double y,
    double width,
    double height,
  ) {
    return BoardPanelInstance(
      id: id,
      type: type,
      title: id,
      bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
    );
  }

  group('GridRect', () {
    test('detects overlaps', () {
      const a = GridRect(0, 0);
      const b = GridRect(1, 0);
      const c = GridRect(0, 1);
      expect(a.overlaps(b), isFalse);
      expect(a.overlaps(c), isFalse);
      expect(a.overlaps(a), isTrue);
    });

    test('detects partial overlaps', () {
      const a = GridRect(0, 0, colSpan: 2, rowSpan: 2);
      const b = GridRect(1, 1);
      expect(a.overlaps(b), isTrue);
    });
  });

  group('boundsToGridRect / gridRectToBounds', () {
    test('round-trips a single cell panel', () {
      final bounds = BoardPanelBounds(
        x: pitch * 3,
        y: pitch * 2,
        width: mode.cellSize,
        height: mode.cellSize,
      );
      final rect = boundsToGridRect(mode, bounds);
      expect(rect.col, 3);
      expect(rect.row, 2);
      expect(rect.colSpan, 1);
      expect(rect.rowSpan, 1);

      final converted = gridRectToBounds(mode, rect);
      expect(converted.x, bounds.x);
      expect(converted.y, bounds.y);
      expect(converted.width, bounds.width);
      expect(converted.height, bounds.height);
    });

    test('computes multi-cell spans', () {
      final bounds = BoardPanelBounds(
        x: 0,
        y: 0,
        width: mode.cellSize * 2 + mode.spacing,
        height: mode.cellSize * 3 + mode.spacing * 2,
      );
      final rect = boundsToGridRect(mode, bounds);
      expect(rect.colSpan, 2);
      expect(rect.rowSpan, 3);
    });
  });

  group('arrangePanelsInCloud', () {
    test('packs panels into a compact cloud', () {
      final panels = [
        makePanel('p1', 'note', 0, 0, 220, 220),
        makePanel('p2', 'chat', 500, 0, 220, 220),
        makePanel('p3', 'note', 1000, 0, 220, 220),
      ];

      final arranged = arrangePanelsInCloud(mode, panels, maxColumns: 4);

      // Three single-cell panels are packed into a roughly 2x2 square.
      expect(arranged[0].bounds.x, 0.0);
      expect(arranged[1].bounds.x, pitch);
      expect(arranged[2].bounds.x, 0.0);
      expect(arranged[2].bounds.y, pitch);
    });

    test('wraps to next row when target width is reached', () {
      final panels = List.generate(
        5,
        (i) => makePanel('p$i', 'note', i * 300.0, 0, 220, 220),
      );

      final arranged = arrangePanelsInCloud(mode, panels, maxColumns: 3);

      final firstRow = arranged.where((p) => p.bounds.y == 0.0).toList();
      final secondRow = arranged.where((p) => p.bounds.y > 0.0).toList();

      expect(firstRow.length, 3);
      expect(secondRow.length, 2);
    });

    test('does not group by type', () {
      final panels = [
        makePanel('p1', 'note', 0, 0, 220, 220),
        makePanel('p2', 'chat', 0, 500, 220, 220),
      ];

      final arranged = arrangePanelsInCloud(mode, panels, maxColumns: 4);

      expect(arranged[0].id, 'p1');
      expect(arranged[1].id, 'p2');
      expect(arranged[1].bounds.y, 0.0);
    });

    test('preserves hidden panels', () {
      final visible = makePanel('visible', 'note', 0, 0, 220, 220);
      const hidden = BoardPanelInstance(
        id: 'hidden',
        type: 'note',
        title: 'hidden',
        bounds: BoardPanelBounds(x: 123, y: 456, width: 220, height: 220),
        hidden: true,
      );

      final arranged = arrangePanelsInCloud(mode, [visible, hidden]);

      final hiddenResult = arranged.firstWhere((p) => p.id == 'hidden');
      expect(hiddenResult.bounds.x, 123.0);
      expect(hiddenResult.bounds.y, 456.0);
    });
  });

  group('pushPanelToRect', () {
    test('snaps panel to target and pushes overlapping neighbor', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch, 0, 220, 220),
      ];

      final moved = pushPanelToRect(mode, panels, 'a', const GridRect(1, 0));

      final a = moved.firstWhere((p) => p.id == 'a');
      final b = moved.firstWhere((p) => p.id == 'b');

      expect(a.bounds.x, pitch);
      expect(b.bounds.x, pitch * 2);
    });

    test('does not move neighbors when there is no overlap', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch * 2, 0, 220, 220),
      ];

      final moved = pushPanelToRect(mode, panels, 'a', const GridRect(1, 0));

      final b = moved.firstWhere((p) => p.id == 'b');
      expect(b.bounds.x, pitch * 2);
    });

    test('cascades push through multiple panels', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch, 0, 220, 220),
        makePanel('c', 'note', pitch * 2, 0, 220, 220),
      ];

      final moved = pushPanelToRect(mode, panels, 'a', const GridRect(1, 0));

      final a = moved.firstWhere((p) => p.id == 'a');
      final b = moved.firstWhere((p) => p.id == 'b');
      final c = moved.firstWhere((p) => p.id == 'c');

      expect(a.bounds.x, pitch);
      expect(b.bounds.x, pitch * 2);
      expect(c.bounds.x, pitch * 3);
    });

    test('pushes panel resized into occupied space', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch, 0, 220, 220),
      ];

      // a grows to two cells wide and overlaps b.
      final resized = pushPanelToRect(
        mode,
        panels,
        'a',
        const GridRect(0, 0, colSpan: 2, rowSpan: 1),
      );

      final a = resized.firstWhere((p) => p.id == 'a');
      final b = resized.firstWhere((p) => p.id == 'b');

      expect(a.bounds.width, mode.cellSize * 2 + mode.spacing);
      expect(b.bounds.x, pitch * 2);
    });
  });

  group('pushPanelInGrid', () {
    test('moves panel to empty cell without changes', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch, 0, 220, 220),
      ];

      final moved = pushPanelInGrid(mode, panels, 'a', 2, 0);

      final a = moved.firstWhere((p) => p.id == 'a');
      final b = moved.firstWhere((p) => p.id == 'b');

      expect(a.bounds.x, pitch * 2);
      expect(b.bounds.x, pitch); // unchanged
    });

    test('pushes neighbor horizontally', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', pitch, 0, 220, 220),
      ];

      final moved = pushPanelInGrid(mode, panels, 'a', 1, 0);

      final a = moved.firstWhere((p) => p.id == 'a');
      final b = moved.firstWhere((p) => p.id == 'b');

      expect(a.bounds.x, pitch);
      expect(b.bounds.x, pitch * 2);
    });

    test('pushes neighbor vertically', () {
      final panels = [
        makePanel('a', 'note', 0, 0, 220, 220),
        makePanel('b', 'note', 0, pitch, 220, 220),
      ];

      final moved = pushPanelInGrid(mode, panels, 'a', 0, 1);

      final a = moved.firstWhere((p) => p.id == 'a');
      final b = moved.firstWhere((p) => p.id == 'b');

      expect(a.bounds.y, pitch);
      expect(b.bounds.y, pitch * 2);
    });
  });

  group('arrangePanelsByType', () {
    test('lays same-type panels next to each other in their block', () {
      final panels = [
        makePanel('a1', 'a', 0, 0, 220, 220),
        makePanel('a2', 'a', 0, 0, 220, 220),
        makePanel('b1', 'b', 0, 0, 220, 220),
      ];

      final arranged = arrangePanelsByType(mode, panels);
      final as = arranged.where((p) => p.type == 'a').toList();
      final bs = arranged.where((p) => p.type == 'b').toList();

      expect(as.length, 2);
      expect(bs.length, 1);
      // Same-type panels are adjacent inside their block.
      expect(as[1].bounds.x, as[0].bounds.x + pitch);
      expect(as[1].bounds.y, as[0].bounds.y);
    });

    test('places different type blocks side-by-side and wraps groups', () {
      final panels = [
        makePanel('a1', 'a', 0, 0, 220, 220),
        makePanel('b1', 'b', 0, 0, 220, 220),
        makePanel('c1', 'c', 0, 0, 220, 220),
        makePanel('d1', 'd', 0, 0, 220, 220),
      ];

      final arranged = arrangePanelsByType(mode, panels);
      final a = arranged.firstWhere((p) => p.type == 'a');
      final b = arranged.firstWhere((p) => p.type == 'b');
      final c = arranged.firstWhere((p) => p.type == 'c');
      final d = arranged.firstWhere((p) => p.type == 'd');

      // 4 single-cell groups are packed into a roughly 2x2 cloud.
      expect(b.bounds.x, greaterThan(a.bounds.x));
      expect(c.bounds.y, greaterThan(a.bounds.y));
      expect(d.bounds.y, c.bounds.y);
      expect(d.bounds.x, b.bounds.x);
    });

    test('wraps panels inside a group', () {
      final panels = List.generate(
        5,
        (i) => makePanel('n$i', 'note', 0, 0, 220, 220),
      );

      final arranged = arrangePanelsByType(mode, panels);
      final firstRow = arranged.where((p) => p.bounds.y == 0.0).toList();
      final wrapped = arranged.where((p) => p.bounds.y > 0.0).toList();

      expect(firstRow.length, 3);
      expect(wrapped.length, 2);
    });
  });

  group('resizeBoundsInGrid', () {
    test('snaps size to cell multiples', () {
      final bounds = BoardPanelBounds(
        x: 0,
        y: 0,
        width: mode.cellSize,
        height: mode.cellSize,
      );
      final resized = resizeBoundsInGrid(
        mode,
        bounds,
        deltaCols: 1,
        deltaRows: 2,
      );
      expect(resized.width, mode.cellSize * 2 + mode.spacing);
      expect(resized.height, mode.cellSize * 3 + mode.spacing * 2);
    });

    test('does not shrink below one cell', () {
      final bounds = BoardPanelBounds(
        x: 0,
        y: 0,
        width: mode.cellSize,
        height: mode.cellSize,
      );
      final resized = resizeBoundsInGrid(
        mode,
        bounds,
        deltaCols: -5,
        deltaRows: -5,
      );
      expect(resized.width, mode.cellSize);
      expect(resized.height, mode.cellSize);
    });
  });
}
