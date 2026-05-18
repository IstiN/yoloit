import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _checklistPanel(Map<String, dynamic> state) => BoardPanelInstance(
      id: 'checklist-panel-1',
      type: 'board.checklist',
      title: 'Shopping List',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 400),
      state: state,
    );

BoardPanelInstance _checklistFromFixture(String fixtureName) =>
    _checklistPanel(_loadFixture(fixtureName));

void main() {
  final handler = const ChecklistCliHandler();

  group('Checklist workflow — user manages shopping list', () {
    test('items returns 4 items with 1 done from checklist_shopping', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('items', {}, panel);
      expect(r.ok, isTrue);
      final items = r.data!['items'] as List;
      expect(items.length, 4);
      final doneCount = items.where((i) => i['done'] == true).length;
      expect(doneCount, 1); // Bread is done
    });

    test('check index=0 marks Milk as done', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('check', {'index': 0}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[0]['text'], 'Milk');
      expect(items[0]['done'], isTrue);
    });

    test('check text="eggs" finds Eggs case-insensitively', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('check', {'text': 'eggs'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      final eggs = items.firstWhere((i) => i['text'] == 'Eggs');
      expect(eggs['done'], isTrue);
    });

    test('check id="item-4" finds Coffee by id', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('check', {'id': 'item-4'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      final coffee = items.firstWhere((i) => i['id'] == 'item-4');
      expect(coffee['done'], isTrue);
    });

    test('uncheck index=1 marks Bread as not done', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('uncheck', {'index': 1}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[1]['text'], 'Bread');
      expect(items[1]['done'], isFalse);
    });

    test('add Butter creates 5 items', () async {
      final panel = _checklistFromFixture('checklist_shopping');
      final r = await handler.handleAction('add', {'text': 'Butter'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 5);
      expect(items.last['text'], 'Butter');
    });

    test('add → rename → remove workflow', () async {
      var panel = _checklistFromFixture('checklist_shopping');

      // Add Butter → 5 items
      final addResult = await handler.handleAction('add', {'text': 'Butter'}, panel);
      expect(addResult.ok, isTrue);
      expect((addResult.stateUpdate!['items'] as List).length, 5);
      panel = _checklistPanel({...panel.state, ...addResult.stateUpdate!});

      // Rename index=4 to Organic Butter
      final renameResult = await handler.handleAction(
        'rename',
        {'index': 4, 'text': 'Organic Butter'},
        panel,
      );
      expect(renameResult.ok, isTrue);
      final afterRename = renameResult.stateUpdate!['items'] as List;
      expect(afterRename[4]['text'], 'Organic Butter');
      panel = _checklistPanel({...panel.state, ...renameResult.stateUpdate!});

      // Remove index=4 → back to 4 items
      final removeResult = await handler.handleAction('remove', {'index': 4}, panel);
      expect(removeResult.ok, isTrue);
      final afterRemove = removeResult.stateUpdate!['items'] as List;
      expect(afterRemove.length, 4);
      expect(afterRemove.any((i) => i['text'] == 'Organic Butter'), isFalse);
    });

    test('full shopping workflow — check all items', () async {
      var panel = _checklistFromFixture('checklist_shopping');

      // Check Milk (index 0)
      final r1 = await handler.handleAction('check', {'index': 0}, panel);
      panel = _checklistPanel({...panel.state, ...r1.stateUpdate!});

      // Check Eggs by text
      final r2 = await handler.handleAction('check', {'text': 'Eggs'}, panel);
      panel = _checklistPanel({...panel.state, ...r2.stateUpdate!});

      // Check Coffee by id
      final r3 = await handler.handleAction('check', {'id': 'item-4'}, panel);
      panel = _checklistPanel({...panel.state, ...r3.stateUpdate!});

      // Verify all 4 items are done (Bread was already done)
      final items = panel.state['items'] as List;
      expect(items.every((i) => i['done'] == true), isTrue);
    });
  });

  group('Checklist workflow — starting from empty list', () {
    test('items from empty fixture returns empty list', () async {
      final panel = _checklistFromFixture('checklist_empty');
      final r = await handler.handleAction('items', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['items'], isEmpty);
    });

    test('add first task to empty list', () async {
      final panel = _checklistFromFixture('checklist_empty');
      final r = await handler.handleAction('add', {'text': 'First task'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 1);
      expect(items[0]['text'], 'First task');
      expect(items[0]['done'], isFalse);
    });

    test('add → check workflow on empty list', () async {
      var panel = _checklistFromFixture('checklist_empty');

      // Add first task
      final addResult = await handler.handleAction('add', {'text': 'First task'}, panel);
      expect(addResult.ok, isTrue);
      panel = _checklistPanel({...panel.state, ...addResult.stateUpdate!});

      // Check it
      final checkResult = await handler.handleAction('check', {'index': 0}, panel);
      expect(checkResult.ok, isTrue);
      final items = checkResult.stateUpdate!['items'] as List;
      expect(items[0]['done'], isTrue);
    });
  });
}
