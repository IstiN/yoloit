import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _panelFromFixture(String fixtureName) {
  final state = _loadFixture(fixtureName);
  return BoardPanelInstance(
    id: 'test-panel-code',
    type: 'board.code.snippet',
    title: 'Code Snippet',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
    state: state,
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'test-panel-code',
      type: 'board.code.snippet',
      title: 'Code Snippet',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

void main() {
  final handler = const CodeSnippetCliHandler();

  group('CodeSnippetCliHandler — metadata', () {
    test('typeId is board.code.snippet', () {
      expect(handler.typeId, 'board.code.snippet');
    });

    test('supportedActions includes get and set', () {
      expect(handler.supportedActions, containsAll(['get', 'set']));
    });
  });

  group('CodeSnippetCliHandler — get action', () {
    test('get from empty fixture returns empty code and plaintext language', () async {
      final panel = _panelFromFixture('code_empty');
      final r = await handler.handleAction('get', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['code'], '');
      expect(r.data!['language'], 'plaintext');
    });

    test('get from code_python fixture returns code and language', () async {
      final panel = _panelFromFixture('code_python');
      final r = await handler.handleAction('get', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['language'], 'python');
      expect(r.data!['code'], contains('fibonacci'));
    });

    test('getContent returns same as get action data', () {
      final panel = _panelFromFixture('code_python');
      final content = handler.getContent(panel);
      expect(content['language'], 'python');
      expect(content['code'], isNotEmpty);
    });
  });

  group('CodeSnippetCliHandler — set action', () {
    test('set with code only updates code', () async {
      final panel = _panelFromFixture('code_python');
      const newCode = 'print("hello world")';
      final r = await handler.handleAction('set', {'code': newCode}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['code'], newCode);
    });

    test('set with code only does not include language in stateUpdate', () async {
      final panel = _panelFromFixture('code_python');
      final r = await handler.handleAction('set', {'code': 'x = 1'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!.containsKey('language'), isFalse);
    });

    test('set with code and language updates both', () async {
      final panel = _panelFromFixture('code_empty');
      final r = await handler.handleAction(
        'set',
        {'code': 'console.log("hi")', 'language': 'javascript'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['code'], 'console.log("hi")');
      expect(r.stateUpdate!['language'], 'javascript');
    });

    test('set without code field returns ok=false', () async {
      final panel = _panelFromFixture('code_empty');
      final r = await handler.handleAction('set', {'language': 'python'}, panel);
      expect(r.ok, isFalse);
    });

    test('set empty args returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('set', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('CodeSnippetCliHandler — unknown action', () {
    test('unknown action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('run', {}, panel);
      expect(r.ok, isFalse);
    });

    test('delete action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('delete', {}, panel);
      expect(r.ok, isFalse);
    });
  });
}
