import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _panelFromFixture(String fixtureName, {String title = 'Test Panel'}) {
  final state = _loadFixture(fixtureName);
  return BoardPanelInstance(
    id: 'test-panel-1',
    type: 'board.checklist',
    title: title,
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
    state: state,
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'test-panel-1',
      type: 'board.checklist',
      title: 'Test Panel',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
      state: state,
    );

void main() {
  final handler = const ChecklistCliHandler();

  group('ChecklistCliHandler — metadata', () {
    test('typeId is board.checklist', () {
      expect(handler.typeId, 'board.checklist');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(['items', 'add', 'check', 'uncheck', 'remove', 'rename']),
      );
    });
  });

  group('ChecklistCliHandler — items action', () {
    test('returns empty list from checklist_empty fixture', () async {
      final panel = _panelFromFixture('checklist_empty');
      final r = await handler.handleAction('items', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['items'], isEmpty);
    });

    test('returns 4 items from checklist_shopping fixture', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('items', {}, panel);
      expect(r.ok, isTrue);
      final items = r.data!['items'] as List;
      expect(items.length, 4);
    });

    test('returns 2 done items from checklist_all_done fixture', () async {
      final panel = _panelFromFixture('checklist_all_done');
      final r = await handler.handleAction('items', {}, panel);
      expect(r.ok, isTrue);
      final items = r.data!['items'] as List;
      expect(items.length, 2);
      expect(items.every((i) => i['done'] == true), isTrue);
    });
  });

  group('ChecklistCliHandler — add action', () {
    test('adds item to empty list', () async {
      final panel = _panelFromFixture('checklist_empty');
      final r = await handler.handleAction('add', {'text': 'Buy milk'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 1);
      expect(items[0]['text'], 'Buy milk');
      expect(items[0]['done'], false);
    });

    test('adds item to non-empty list', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('add', {'text': 'Butter'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 5);
      expect(items.last['text'], 'Butter');
    });

    test('returns ok=false when text is missing', () async {
      final panel = _panelFromFixture('checklist_empty');
      final r = await handler.handleAction('add', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('ChecklistCliHandler — check action', () {
    test('check by index marks item done', () async {
      final panel = _panelFromFixture('checklist_shopping');
      // index 0 = Milk (done: false)
      final r = await handler.handleAction('check', {'index': 0}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[0]['done'], isTrue);
    });

    test('check by id finds item by id field', () async {
      final panel = _panelFromFixture('checklist_shopping');
      // item-4 = Coffee
      final r = await handler.handleAction('check', {'id': 'item-4'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      final coffee = items.firstWhere((i) => i['id'] == 'item-4');
      expect(coffee['done'], isTrue);
    });

    test('check by text finds item case-insensitively', () async {
      final panel = _panelFromFixture('checklist_shopping');
      // "eggs" should match "Eggs"
      final r = await handler.handleAction('check', {'text': 'eggs'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      final eggs = items.firstWhere((i) => i['text'] == 'Eggs');
      expect(eggs['done'], isTrue);
    });

    test('check on missing item returns ok=false', () async {
      final panel = _panelFromFixture('checklist_empty');
      final r = await handler.handleAction('check', {'index': 0}, panel);
      expect(r.ok, isFalse);
    });

    test('check with no selector returns ok=false', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('check', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('ChecklistCliHandler — uncheck action', () {
    test('uncheck marks done item as not done', () async {
      final panel = _panelFromFixture('checklist_shopping');
      // index 1 = Bread (done: true)
      final r = await handler.handleAction('uncheck', {'index': 1}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[1]['done'], isFalse);
    });

    test('uncheck by id', () async {
      final panel = _panelFromFixture('checklist_all_done');
      final r = await handler.handleAction('uncheck', {'id': 'item-1'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[0]['done'], isFalse);
    });
  });

  group('ChecklistCliHandler — remove action', () {
    test('remove by index removes item and returns updated list', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('remove', {'index': 0}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 3);
      // Milk should be gone
      expect(items.any((i) => i['text'] == 'Milk'), isFalse);
    });

    test('remove out of range returns ok=false', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('remove', {'index': 99}, panel);
      expect(r.ok, isFalse);
    });

    test('remove without index returns ok=false', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('remove', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('ChecklistCliHandler — rename action', () {
    test('rename by index updates text', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('rename', {'index': 0, 'text': 'Oat Milk'}, panel);
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items[0]['text'], 'Oat Milk');
    });

    test('rename out of range returns ok=false', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('rename', {'index': 99, 'text': 'X'}, panel);
      expect(r.ok, isFalse);
    });

    test('rename without text returns ok=false', () async {
      final panel = _panelFromFixture('checklist_shopping');
      final r = await handler.handleAction('rename', {'index': 0}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('ChecklistCliHandler — unknown action', () {
    test('unknown action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('delete-all', {}, panel);
      expect(r.ok, isFalse);
    });
  });
}
