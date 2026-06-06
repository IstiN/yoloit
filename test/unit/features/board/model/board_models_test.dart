import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  group('BoardDrawingElement', () {
    test('serializes to JSON and back', () {
      const element = BoardDrawingElement(
        id: 'd1',
        strokes: [
          [Offset(0, 0), Offset(10, 10)],
        ],
        position: Offset(100, 100),
        size: Size(50, 50),
        strokeColor: Colors.red,
        strokeWidth: 2,
        zIndex: 1,
        hidden: true,
      );
      final json = element.toJson();
      final restored = BoardDrawingElement.fromJson(json);
      expect(restored.id, 'd1');
      expect(restored.strokes.first.first.dx, 0);
      expect(restored.position.dx, 100);
      expect(restored.size.width, 50);
      expect(restored.strokeColor.toARGB32(), Colors.red.toARGB32());
      expect(restored.strokeWidth, 2);
      expect(restored.zIndex, 1);
      expect(restored.hidden, true);
    });

    test('fromJson handles missing fields with defaults', () {
      final restored = BoardDrawingElement.fromJson(const <String, dynamic>{
        'id': 'd2',
        'strokes': [],
        'strokeColor': 0xFF000000,
      });
      expect(restored.position, Offset.zero);
      expect(restored.size, const Size(100, 100));
      expect(restored.strokeWidth, 3);
      expect(restored.zIndex, 0);
      expect(restored.hidden, false);
    });

    test('fromRawStroke builds relative strokes and bbox', () {
      final element = BoardDrawingElement.fromRawStroke(
        id: 'd3',
        rawPoints: const [Offset(10, 10), Offset(30, 40)],
        strokeColor: Colors.blue,
        strokeWidth: 4,
      );
      expect(element.strokes.first.first, Offset(8, 8));
      expect(element.position.dx, 2);
      expect(element.position.dy, 2);
      expect(element.size.width, 36);
      expect(element.size.height, 46);
    });

    test('bounds returns position & size rect', () {
      const element = BoardDrawingElement(
        id: 'd1',
        strokes: [],
        position: Offset(5, 5),
        size: Size(10, 20),
        strokeColor: Colors.black,
        strokeWidth: 1,
      );
      expect(element.bounds, const Rect.fromLTWH(5, 5, 10, 20));
    });

    test('copyWith replaces fields', () {
      const element = BoardDrawingElement(
        id: 'd1',
        strokes: [],
        position: Offset.zero,
        size: Size.zero,
        strokeColor: Colors.black,
        strokeWidth: 1,
      );
      final updated = element.copyWith(strokeColor: Colors.green, strokeWidth: 5);
      expect(updated.strokeColor.toARGB32(), Colors.green.toARGB32());
      expect(updated.strokeWidth, 5);
      expect(updated.id, 'd1');
    });
  });

  group('BoardViewport', () {
    test('serializes to JSON and back', () {
      const viewport = BoardViewport(
        scale: 1.5,
        translation: Offset(10, 20),
        focusedPanelId: 'p1',
      );
      final json = viewport.toJson();
      final restored = BoardViewport.fromJson(json);
      expect(restored.scale, 1.5);
      expect(restored.translation, const Offset(10, 20));
      expect(restored.focusedPanelId, 'p1');
    });

    test('fromJson uses defaults', () {
      final restored = BoardViewport.fromJson(const <String, dynamic>{});
      expect(restored.scale, 1);
      expect(restored.translation, Offset.zero);
      expect(restored.focusedPanelId, isNull);
    });

    test('copyWith clears focusedPanelId', () {
      const viewport = BoardViewport(focusedPanelId: 'p1');
      final cleared = viewport.copyWith(clearFocusedPanelId: true);
      expect(cleared.focusedPanelId, isNull);
    });
  });

  group('BoardPanelBounds', () {
    test('serializes to JSON and back', () {
      const bounds = BoardPanelBounds(x: 1, y: 2, width: 3, height: 4);
      final json = bounds.toJson();
      final restored = BoardPanelBounds.fromJson(json);
      expect(restored.x, 1);
      expect(restored.y, 2);
      expect(restored.width, 3);
      expect(restored.height, 4);
    });

    test('fromJson uses defaults', () {
      final restored = BoardPanelBounds.fromJson(const <String, dynamic>{});
      expect(restored.x, 0);
      expect(restored.y, 0);
      expect(restored.width, 320);
      expect(restored.height, 220);
    });

    test('computed getters', () {
      const bounds = BoardPanelBounds(x: 5, y: 6, width: 7, height: 8);
      expect(bounds.offset, const Offset(5, 6));
      expect(bounds.size, const Size(7, 8));
      expect(bounds.rect, const Rect.fromLTWH(5, 6, 7, 8));
    });

    test('copyWith replaces fields', () {
      const bounds = BoardPanelBounds(x: 0, y: 0, width: 10, height: 10);
      final updated = bounds.copyWith(width: 20);
      expect(updated.width, 20);
      expect(updated.height, 10);
    });
  });

  group('BoardPanelInstance', () {
    test('serializes to JSON and back', () {
      const panel = BoardPanelInstance(
        id: 'p1',
        type: 'note',
        title: 'Notes',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        color: Colors.red,
        params: {'a': 1},
        state: {'text': 'hi'},
        zIndex: 2,
        hidden: true,
        locked: true,
        pinned: true,
      );
      final json = panel.toJson();
      final restored = BoardPanelInstance.fromJson(json);
      expect(restored.id, 'p1');
      expect(restored.type, 'note');
      expect(restored.title, 'Notes');
      expect(restored.bounds.width, 100);
      expect(restored.color?.toARGB32(), Colors.red.toARGB32());
      expect(restored.params['a'], 1);
      expect(restored.state['text'], 'hi');
      expect(restored.zIndex, 2);
      expect(restored.hidden, true);
      expect(restored.locked, true);
      expect(restored.pinned, true);
    });

    test('fromJson uses defaults', () {
      final restored = BoardPanelInstance.fromJson(const <String, dynamic>{
        'id': 'p2',
        'type': 'chat',
        'bounds': {},
      });
      expect(restored.title, 'Panel');
      expect(restored.color, isNull);
      expect(restored.zIndex, 0);
      expect(restored.hidden, false);
    });

    test('copyWith clears color', () {
      const panel = BoardPanelInstance(
        id: 'p1',
        type: 'note',
        title: 'T',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
        color: Colors.red,
      );
      final updated = panel.copyWith(clearColor: true);
      expect(updated.color, isNull);
    });
  });

  group('BoardPanelLink', () {
    test('serializes to JSON and back', () {
      const link = BoardPanelLink(
        id: 'l1',
        fromPanelId: 'a',
        toPanelId: 'b',
        style: BoardLinkStyle.line,
        behavior: BoardLinkBehavior.dynamic,
        color: Colors.red,
        geometry: BoardLinkGeometry.straight,
      );
      final json = link.toJson();
      final restored = BoardPanelLink.fromJson(json);
      expect(restored.id, 'l1');
      expect(restored.style, BoardLinkStyle.line);
      expect(restored.behavior, BoardLinkBehavior.dynamic);
      expect(restored.color.toARGB32(), Colors.red.toARGB32());
      expect(restored.geometry, BoardLinkGeometry.straight);
    });

    test('fromJson uses defaults', () {
      final restored = BoardPanelLink.fromJson(const <String, dynamic>{
        'id': 'l2',
        'fromPanelId': 'a',
        'toPanelId': 'b',
      });
      expect(restored.style, BoardLinkStyle.arrow);
      expect(restored.behavior, BoardLinkBehavior.fixed);
      expect(restored.geometry, BoardLinkGeometry.bezier);
    });

    test('copyWith replaces fields', () {
      const link = BoardPanelLink(id: 'l1', fromPanelId: 'a', toPanelId: 'b');
      final updated = link.copyWith(color: Colors.green);
      expect(updated.color.toARGB32(), Colors.green.toARGB32());
      expect(updated.fromPanelId, 'a');
    });
  });

  group('BoardDocument', () {
    test('serializes full document to JSON and back', () {
      const doc = BoardDocument(
        id: 'b1',
        name: 'My Board',
        viewport: BoardViewport(scale: 2, translation: Offset(5, 5)),
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'note',
            title: 'N',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        ],
        links: [
          BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2'),
        ],
        drawings: [
          BoardDrawingElement(
            id: 'd1',
            strokes: [],
            position: Offset.zero,
            size: Size.zero,
            strokeColor: Colors.black,
            strokeWidth: 1,
          ),
        ],
        metadata: {'defaultFolder': '/tmp'},
      );
      final json = doc.toJson();
      final restored = BoardDocument.fromJson(json);
      expect(restored.id, 'b1');
      expect(restored.name, 'My Board');
      expect(restored.viewport.scale, 2);
      expect(restored.panels.length, 1);
      expect(restored.links.length, 1);
      expect(restored.drawings.length, 1);
      expect(restored.defaultFolder, '/tmp');
    });

    test('fromJson uses defaults', () {
      final restored = BoardDocument.fromJson(const <String, dynamic>{
        'id': 'b2',
      });
      expect(restored.name, 'Board');
      expect(restored.viewport.scale, 1);
      expect(restored.panels, isEmpty);
      expect(restored.links, isEmpty);
      expect(restored.drawings, isEmpty);
      expect(restored.defaultFolder, '');
    });

    test('copyWith replaces nested lists', () {
      const doc = BoardDocument(id: 'b1', name: 'B');
      final updated = doc.copyWith(
        panels: [
          const BoardPanelInstance(
            id: 'p1',
            type: 'note',
            title: 'T',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 1, height: 1),
          ),
        ],
      );
      expect(updated.panels.length, 1);
      expect(updated.name, 'B');
    });
  });

  group('Enums', () {
    test('BoardLinkStyle has expected values', () {
      expect(BoardLinkStyle.values, contains(BoardLinkStyle.line));
      expect(BoardLinkStyle.values, contains(BoardLinkStyle.arrow));
    });

    test('BoardLinkBehavior has expected values', () {
      expect(BoardLinkBehavior.values, contains(BoardLinkBehavior.fixed));
      expect(BoardLinkBehavior.values, contains(BoardLinkBehavior.dynamic));
    });

    test('BoardLinkGeometry has expected values', () {
      expect(BoardLinkGeometry.values, contains(BoardLinkGeometry.bezier));
      expect(BoardLinkGeometry.values, contains(BoardLinkGeometry.straight));
      expect(BoardLinkGeometry.values, contains(BoardLinkGeometry.elbow));
    });
  });
}
