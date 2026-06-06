import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/board_svg_exporter.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardPanelInstance _panel({
    required String id,
    required double x,
    required double y,
    double width = 200,
    double height = 150,
    String type = 'board.chat',
    String title = 'Panel',
    bool hidden = false,
  }) =>
      BoardPanelInstance(
        id: id,
        type: type,
        title: title,
        bounds: BoardPanelBounds(x: x, y: y, width: width, height: height),
        hidden: hidden,
      );

  group('BoardSvgExporter.export', () {
    test('returns fallback SVG for empty board', () {
      final board = BoardDocument(id: 'empty', name: 'Empty');
      final svg = BoardSvgExporter.export(board);

      expect(svg, startsWith('<?xml'));
      expect(svg, contains('width="800"'));
      expect(svg, contains('height="600"'));
    });

    test('includes board title text', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Test & Board',
        panels: [_panel(id: 'p1', x: 0, y: 0)],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('Test &amp; Board'));
    });

    test('renders panel rect and title', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [_panel(id: 'p1', x: 10, y: 20, title: 'Chat Panel')],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('class="panel"'));
      expect(svg, contains('Chat Panel'));
      expect(svg, contains('class="panel-title"'));
    });

    test('renders type label without board. prefix', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [_panel(id: 'p1', x: 0, y: 0, type: 'board.terminal')],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('>terminal<'));
    });

    test('renders dimensions label', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [_panel(id: 'p1', x: 0, y: 0, width: 320, height: 240)],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('320×240'));
    });

    test('renders link line between panels', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [
          _panel(id: 'p1', x: 0, y: 0, width: 100, height: 100),
          _panel(id: 'p2', x: 200, y: 0, width: 100, height: 100),
        ],
        links: [
          const BoardPanelLink(
            id: 'l1',
            fromPanelId: 'p1',
            toPanelId: 'p2',
          ),
        ],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('<line'));
      expect(svg, contains('class="link"'));
    });

    test('skips hidden panels', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [
          _panel(id: 'p1', x: 0, y: 0, title: 'Visible'),
          _panel(id: 'p2', x: 0, y: 200, title: 'Hidden', hidden: true),
        ],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('Visible'));
      expect(svg, isNot(contains('Hidden')));
    });

    test('skips links with missing panels', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [_panel(id: 'p1', x: 0, y: 0)],
        links: [
          const BoardPanelLink(
            id: 'l1',
            fromPanelId: 'p1',
            toPanelId: 'missing',
          ),
        ],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, isNot(contains('x1="')));
    });

    test('escapes HTML special characters in title', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: [_panel(id: 'p1', x: 0, y: 0, title: '<script>"alert"')],
      );
      final svg = BoardSvgExporter.export(board);

      expect(svg, contains('&lt;script&gt;&quot;alert&quot;'));
      expect(svg, isNot(contains('<script>')));
    });
  });

  group('BoardSvgExporter.exportDrawings', () {
    test('returns fallback when no drawings exist', () {
      final board = BoardDocument(id: 'b1', name: 'Board');
      final svg = BoardSvgExporter.exportDrawings(board);

      expect(svg, startsWith('<?xml'));
      expect(svg, contains('no drawings'));
    });

    test('renders drawing strokes as SVG path', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [
              [const Offset(0, 0), const Offset(10, 10)],
            ],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.red,
            strokeWidth: 2,
          ),
        ],
      );
      final svg = BoardSvgExporter.exportDrawings(board);

      expect(svg, contains('<path'));
      expect(svg, contains('M '));
      expect(svg, contains(' L '));
      expect(svg, contains('stroke="#f44336"'));
    });

    test('skips hidden drawings', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [
              [const Offset(0, 0), const Offset(10, 10)],
            ],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.red,
            strokeWidth: 2,
            hidden: true,
          ),
          BoardDrawingElement(
            id: 'd2',
            strokes: [
              [const Offset(50, 50), const Offset(60, 60)],
            ],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.blue,
            strokeWidth: 2,
          ),
        ],
      );
      final svg = BoardSvgExporter.exportDrawings(board);

      expect(svg, isNot(contains('stroke="#f44336"')));
      expect(svg, contains('stroke="#2196f3"'));
    });

    test('skips empty strokes', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [[]],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.red,
            strokeWidth: 2,
          ),
        ],
      );
      final svg = BoardSvgExporter.exportDrawings(board);

      expect(svg, isNot(contains('<path')));
    });

    test('drawings are sorted by zIndex', () {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [
              [const Offset(0, 0), const Offset(5, 5)],
            ],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.red,
            strokeWidth: 2,
            zIndex: 2,
          ),
          BoardDrawingElement(
            id: 'd2',
            strokes: [
              [const Offset(10, 10), const Offset(15, 15)],
            ],
            position: const Offset(100, 100),
            size: const Size(20, 20),
            strokeColor: Colors.blue,
            strokeWidth: 2,
            zIndex: 1,
          ),
        ],
      );
      final svg = BoardSvgExporter.exportDrawings(board);

      // Both should appear, order in SVG is zIndex-sorted (lower zIndex first).
      final redIndex = svg.indexOf('stroke="#f44336"');
      final blueIndex = svg.indexOf('stroke="#2196f3"');
      expect(redIndex, greaterThan(-1));
      expect(blueIndex, greaterThan(-1));
      expect(blueIndex, lessThan(redIndex));
    });
  });
}
