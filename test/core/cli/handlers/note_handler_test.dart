import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/note_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.note.markdown',
      title: 'Note',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      state: state,
    );

void main() {
  final handler = const NoteCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.note.markdown');
  });

  test('supportedActions', () {
    expect(handler.supportedActions, containsAll(['get', 'set', 'append']));
  });

  test('getContent returns markdown', () {
    final panel = _panel(state: {'markdown': '# Hello'});
    expect(handler.getContent(panel), {'markdown': '# Hello'});
  });

  test('getContent returns empty string when no content', () {
    expect(handler.getContent(_panel()), {'markdown': ''});
  });

  test('action get returns markdown', () async {
    final panel = _panel(state: {'markdown': 'text'});
    final r = await handler.handleAction('get', {}, panel);
    expect(r.ok, isTrue);
    expect(r.data!['markdown'], 'text');
  });

  test('action set updates markdown via text', () async {
    final r = await handler.handleAction('set', {'text': 'new'}, _panel());
    expect(r.ok, isTrue);
    expect(r.stateUpdate!['markdown'], 'new');
  });

  test('action set updates markdown via markdown key', () async {
    final r = await handler.handleAction('set', {'markdown': 'new'}, _panel());
    expect(r.ok, isTrue);
    expect(r.stateUpdate!['markdown'], 'new');
  });

  test('action set requires text or markdown', () async {
    final r = await handler.handleAction('set', {}, _panel());
    expect(r.ok, isFalse);
  });

  test('action append appends text', () async {
    final panel = _panel(state: {'markdown': 'A'});
    final r = await handler.handleAction('append', {'text': 'B'}, panel);
    expect(r.ok, isTrue);
    expect(r.stateUpdate!['markdown'], 'A\nB');
  });

  test('unknown action fails', () async {
    final r = await handler.handleAction('delete', {}, _panel());
    expect(r.ok, isFalse);
  });
}
