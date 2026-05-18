import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/kanban_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _kanbanPanel(Map<String, dynamic> state) => BoardPanelInstance(
      id: 'kanban-panel-1',
      type: 'board.kanban',
      title: 'Sprint Board',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 800, height: 600),
      state: state,
    );

BoardPanelInstance _kanbanFromFixture(String fixtureName) =>
    _kanbanPanel(_loadFixture(fixtureName));

void main() {
  final handler = const KanbanCliHandler();

  group('Kanban workflow — PM manages sprint board', () {
    test('columns returns 3 columns from kanban_sprint', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction('columns', {}, panel);
      expect(r.ok, isTrue);
      final cols = r.data!['columns'] as List;
      expect(cols.length, 3);
      final titles = cols.map((c) => c['title']).toList();
      expect(titles, containsAll(['Todo', 'In Progress', 'Done']));
    });

    test('cards returns cards nested under columns', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction('cards', {}, panel);
      expect(r.ok, isTrue);
      final cols = r.data!['columns'] as List;
      expect(cols.length, 3);
      final todo = cols.firstWhere((c) => c['title'] == 'Todo') as Map;
      final todoCards = todo['cards'] as List;
      expect(todoCards.length, 2);
    });

    test('add-card to Todo creates 5 cards total', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction(
        'add-card',
        {'column': 'Todo', 'title': 'Write unit tests'},
        panel,
      );
      expect(r.ok, isTrue);
      final cards = r.stateUpdate!['cards'] as List;
      expect(cards.length, 5);
      expect(cards.any((c) => c['title'] == 'Write unit tests'), isTrue);
    });

    test('move-card moves card to Done column', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction(
        'move-card',
        {'cardId': 'card-1', 'to': 'Done'},
        panel,
      );
      expect(r.ok, isTrue);
      final cards = r.stateUpdate!['cards'] as List;
      final moved = cards.firstWhere((c) => c['id'] == 'card-1') as Map;
      expect(moved['columnIndex'], 2); // Done is index 2
    });

    test('update-card changes card description', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction(
        'update-card',
        {'cardId': 'card-2', 'description': 'Added swagger docs'},
        panel,
      );
      expect(r.ok, isTrue);
      final cards = r.stateUpdate!['cards'] as List;
      final card = cards.firstWhere((c) => c['id'] == 'card-2') as Map;
      expect(card['description'], 'Added swagger docs');
    });

    test('remove-card removes the card from the board', () async {
      final panel = _kanbanFromFixture('kanban_sprint');
      final r = await handler.handleAction('remove-card', {'cardId': 'card-3'}, panel);
      expect(r.ok, isTrue);
      final cards = r.stateUpdate!['cards'] as List;
      expect(cards.length, 3);
      expect(cards.any((c) => c['id'] == 'card-3'), isFalse);
    });

    test('add-card → move-card workflow', () async {
      var panel = _kanbanFromFixture('kanban_sprint');

      // Add a card to Todo
      final addResult = await handler.handleAction(
        'add-card',
        {'column': 'Todo', 'title': 'New feature'},
        panel,
      );
      expect(addResult.ok, isTrue);
      final newCardId = addResult.data!['cardId'] as String;
      panel = _kanbanPanel({...panel.state, ...addResult.stateUpdate!});

      // Move it to In Progress
      final moveResult = await handler.handleAction(
        'move-card',
        {'cardId': newCardId, 'to': 'In Progress'},
        panel,
      );
      expect(moveResult.ok, isTrue);
      final cards = moveResult.stateUpdate!['cards'] as List;
      final moved = cards.firstWhere((c) => c['id'] == newCardId) as Map;
      expect(moved['columnIndex'], 1); // In Progress is index 1
    });
  });

  group('Kanban workflow — building board from empty state', () {
    test('add-column to empty board creates first column', () async {
      final panel = _kanbanFromFixture('kanban_empty');
      final r = await handler.handleAction('add-column', {'name': 'Backlog'}, panel);
      expect(r.ok, isTrue);
      final cols = r.stateUpdate!['columns'] as List;
      expect(cols.length, 1);
      expect(cols[0], 'Backlog');
    });

    test('add two columns then add a card workflow', () async {
      var panel = _kanbanFromFixture('kanban_empty');

      // Add first column
      final r1 = await handler.handleAction('add-column', {'name': 'Backlog'}, panel);
      expect(r1.ok, isTrue);
      panel = _kanbanPanel({...panel.state, ...r1.stateUpdate!});

      // Add second column
      final r2 = await handler.handleAction('add-column', {'name': 'Done'}, panel);
      expect(r2.ok, isTrue);
      panel = _kanbanPanel({...panel.state, ...r2.stateUpdate!});
      expect((panel.state['columns'] as List).length, 2);

      // Add a card to Backlog
      final r3 = await handler.handleAction(
        'add-card',
        {'column': 'Backlog', 'title': 'First task'},
        panel,
      );
      expect(r3.ok, isTrue);
      final cards = r3.stateUpdate!['cards'] as List;
      expect(cards.length, 1);
      expect(cards[0]['title'], 'First task');
      expect(cards[0]['columnIndex'], 0);
    });

    test('rename-column updates column name', () async {
      var panel = _kanbanFromFixture('kanban_empty');

      final addResult = await handler.handleAction('add-column', {'name': 'Backlog'}, panel);
      panel = _kanbanPanel({...panel.state, ...addResult.stateUpdate!});

      final renameResult = await handler.handleAction(
        'rename-column',
        {'column': 'Backlog', 'name': 'Todo'},
        panel,
      );
      expect(renameResult.ok, isTrue);
      final cols = renameResult.stateUpdate!['columns'] as List;
      expect(cols.contains('Todo'), isTrue);
      expect(cols.contains('Backlog'), isFalse);
    });

    test('remove-column removes the column', () async {
      var panel = _kanbanFromFixture('kanban_empty');

      // Add two columns
      final r1 = await handler.handleAction('add-column', {'name': 'Todo'}, panel);
      panel = _kanbanPanel({...panel.state, ...r1.stateUpdate!});
      final r2 = await handler.handleAction('add-column', {'name': 'Done'}, panel);
      panel = _kanbanPanel({...panel.state, ...r2.stateUpdate!});

      // Remove one
      final removeResult = await handler.handleAction('remove-column', {'column': 'Done'}, panel);
      expect(removeResult.ok, isTrue);
      final cols = removeResult.stateUpdate!['columns'] as List;
      expect(cols.length, 1);
      expect(cols.contains('Done'), isFalse);
    });
  });
}
