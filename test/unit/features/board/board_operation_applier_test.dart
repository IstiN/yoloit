import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_operation_applier.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardOperationApplier — buildDocument', () {
    const applier = BoardOperationApplier();

    test('creates panels from operations', () {
      final board = BoardDocument(id: 'b1', name: 'Test');
      final result = applier.buildDocument(board, [
        {
          'op': 'panel.create',
          'type': 'board.note.markdown',
          'title': 'Note',
          'x': 10,
          'y': 20,
          'width': 200,
          'height': 150,
        },
        {
          'op': 'panel.create',
          'type': 'board.kanban',
          'title': 'Kanban',
          'x': 250,
          'y': 20,
        },
      ]);

      expect(result.panels.length, 2);
      expect(result.panels.first.type, 'board.note.markdown');
      expect(result.panels.first.title, 'Note');
      expect(result.panels.first.bounds.x, 10);
      expect(result.panels[1].type, 'board.kanban');
    });

    test('applies board.configure fields', () {
      final board = BoardDocument(id: 'b1', name: 'Test');
      final result = applier.buildDocument(board, [
        {
          'op': 'board.configure',
          'name': 'Renamed',
          'defaultFolder': '/tmp',
          'archived': true,
        },
      ]);

      expect(result.name, 'Renamed');
      expect(result.defaultFolder, '/tmp');
      expect(result.archived, isTrue);
    });

    test('fits viewport to visible panels', () {
      final board = BoardDocument(id: 'b1', name: 'Test');
      final result = applier.buildDocument(board, [
        {
          'op': 'panel.create',
          'type': 'board.note.markdown',
          'x': 100,
          'y': 100,
          'width': 200,
          'height': 200,
        },
        {'op': 'board.fit'},
      ]);

      expect(result.panels.length, 1);
      expect(result.viewport.scale, greaterThan(0));
      expect(result.viewport.translation, isNot(Offset.zero));
    });

    test('link.create resolves panel ids', () {
      final board = BoardDocument(id: 'b1', name: 'Test');
      final result = applier.buildDocument(board, [
        {
          'op': 'panel.create',
          'type': 'board.note.markdown',
          'ref': 'a',
        },
        {
          'op': 'panel.create',
          'type': 'board.note.markdown',
          'ref': 'b',
        },
        {
          'op': 'link.create',
          'from': 'a',
          'to': 'b',
        },
      ]);

      expect(result.links.length, 1);
      expect(result.links.first.fromPanelId, result.panels[0].id);
      expect(result.links.first.toPanelId, result.panels[1].id);
    });
  });
}
