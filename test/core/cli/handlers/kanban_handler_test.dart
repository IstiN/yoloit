import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/kanban_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.kanban',
      title: 'Kanban',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      state: state,
    );

Map<String, dynamic> _withColumns() => {
      'columns': [
        {'id': 'col-1', 'title': 'Todo'},
        {'id': 'col-2', 'title': 'Done'},
      ],
      'cards': [
        {'id': 'card-1', 'columnId': 'col-1', 'title': 'Task A'},
        {'id': 'card-2', 'columnId': 'col-1', 'title': 'Task B'},
      ],
    };

void main() {
  final handler = const KanbanCliHandler();

  test('typeId matches', () => expect(handler.typeId, 'board.kanban'));

  test('columns action lists columns', () async {
    final r = await handler.handleAction('columns', {}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    expect((r.data!['columns'] as List).length, 2);
  });

  test('cards action returns content with nested cards', () async {
    final r = await handler.handleAction('cards', {}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    final cols = r.data!['columns'] as List;
    final todo = cols.firstWhere((c) => c['title'] == 'Todo');
    expect((todo['cards'] as List).length, 2);
  });

  test('add-column', () async {
    final r = await handler.handleAction('add-column', {'name': 'WIP'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    expect((r.stateUpdate!['columns'] as List).length, 3);
  });

  test('rename-column by title', () async {
    final r = await handler.handleAction(
        'rename-column', {'column': 'Todo', 'name': 'Backlog'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    final cols = r.stateUpdate!['columns'] as List;
    expect(cols.contains('Backlog'), isTrue);
  });

  test('remove-column by title', () async {
    final r = await handler.handleAction('remove-column', {'column': 'Done'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    expect((r.stateUpdate!['columns'] as List).length, 1);
  });

  test('add-card by column title', () async {
    final r = await handler.handleAction(
        'add-card', {'column': 'Todo', 'title': 'New'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    final cards = r.stateUpdate!['cards'] as List;
    expect(cards.length, 3);
  });

  test('move-card by cardId', () async {
    final r = await handler.handleAction(
        'move-card', {'cardId': 'card-1', 'to': 'Done'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    final cards = r.stateUpdate!['cards'] as List;
    final moved = cards.firstWhere((c) => c['id'] == 'card-1');
    // Handler converts column ids to column index (Done is at index 1)
    expect(moved['columnIndex'], 1);
  });

  test('remove-card by cardId', () async {
    final r = await handler.handleAction(
        'remove-card', {'cardId': 'card-1'}, _panel(state: _withColumns()));
    expect(r.ok, isTrue);
    final cards = r.stateUpdate!['cards'] as List;
    expect(cards.length, 1);
  });
}
