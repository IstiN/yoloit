import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/note_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _notePanel(Map<String, dynamic> state) => BoardPanelInstance(
      id: 'note-panel-1',
      type: 'board.note.markdown',
      title: 'Note',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

BoardPanelInstance _noteFromFixture(String fixtureName) =>
    _notePanel(_loadFixture(fixtureName));

void main() {
  final handler = const NoteCliHandler();

  group('Note workflow — developer edits project README', () {
    test('get returns existing markdown content', () async {
      final panel = _noteFromFixture('note_project_readme');
      final r = await handler.handleAction('get', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['markdown'], contains('My Project'));
      expect(r.data!['markdown'], contains('Launch MVP by Friday'));
    });

    test('set replaces markdown content', () async {
      final panel = _noteFromFixture('note_project_readme');
      const newContent = '# Updated README\n\nProject is complete.';
      final r = await handler.handleAction('set', {'text': newContent}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['markdown'], newContent);
    });

    test('append adds content to existing markdown', () async {
      final panel = _noteFromFixture('note_project_readme');
      final r = await handler.handleAction('append', {'text': '## Next Steps\n- Ship it!'}, panel);
      expect(r.ok, isTrue);
      final updated = r.stateUpdate!['markdown'] as String;
      expect(updated, contains('My Project'));
      expect(updated, contains('Next Steps'));
    });

    test('get → set → get workflow preserves content integrity', () async {
      var panel = _noteFromFixture('note_project_readme');

      // Step 1: get
      final getResult = await handler.handleAction('get', {}, panel);
      expect(getResult.ok, isTrue);
      final original = getResult.data!['markdown'] as String;
      expect(original, isNotEmpty);

      // Step 2: set with new content
      const updated = '# Rewritten\nNew content here.';
      final setResult = await handler.handleAction('set', {'text': updated}, panel);
      expect(setResult.ok, isTrue);

      // Step 3: apply stateUpdate and get again
      panel = _notePanel({...panel.state, ...setResult.stateUpdate!});
      final getResult2 = await handler.handleAction('get', {}, panel);
      expect(getResult2.data!['markdown'], updated);
    });

    test('append workflow chains correctly', () async {
      var panel = _noteFromFixture('note_project_readme');

      // Append first line
      final r1 = await handler.handleAction('append', {'text': '## Changelog'}, panel);
      expect(r1.ok, isTrue);
      panel = _notePanel({...panel.state, ...r1.stateUpdate!});

      // Append second line
      final r2 = await handler.handleAction('append', {'text': '- Added feature X'}, panel);
      expect(r2.ok, isTrue);
      final finalMarkdown = r2.stateUpdate!['markdown'] as String;
      expect(finalMarkdown, contains('My Project'));
      expect(finalMarkdown, contains('## Changelog'));
      expect(finalMarkdown, contains('Added feature X'));
    });
  });

  group('Note workflow — empty note', () {
    test('get from empty note returns empty markdown', () async {
      final panel = _noteFromFixture('empty_note');
      final r = await handler.handleAction('get', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['markdown'], '');
    });

    test('set on empty note establishes content', () async {
      final panel = _noteFromFixture('empty_note');
      const content = '# Brand New Note\n\nHello world!';
      final r = await handler.handleAction('set', {'text': content}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['markdown'], content);
    });

    test('set → append workflow starting from empty', () async {
      var panel = _noteFromFixture('empty_note');

      final setResult = await handler.handleAction('set', {'text': '# Start'}, panel);
      expect(setResult.ok, isTrue);
      panel = _notePanel({...panel.state, ...setResult.stateUpdate!});

      final appendResult = await handler.handleAction('append', {'text': 'More content'}, panel);
      expect(appendResult.ok, isTrue);
      expect(appendResult.stateUpdate!['markdown'], '# Start\nMore content');
    });
  });

  group('Note workflow — meeting notes fixture', () {
    test('get returns meeting notes content', () async {
      final panel = _noteFromFixture('note_meeting_notes');
      final r = await handler.handleAction('get', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['markdown'], contains('Meeting 2025-05-18'));
      expect(r.data!['markdown'], contains('Alice, Bob, Charlie'));
    });

    test('append adds action item to meeting notes', () async {
      final panel = _noteFromFixture('note_meeting_notes');
      final r = await handler.handleAction('append', {'text': '4. Review PRs'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['markdown'], contains('Review PRs'));
      expect(r.stateUpdate!['markdown'], contains('Fix login bug'));
    });
  });
}
