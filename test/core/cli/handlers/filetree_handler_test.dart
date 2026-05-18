import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/filetree_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

Map<String, dynamic> _loadFixture(String name) {
  final file = File('test/fixtures/demo_states/$name.json');
  return jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
}

BoardPanelInstance _panelFromFixture(String fixtureName) {
  final state = _loadFixture(fixtureName);
  return BoardPanelInstance(
    id: 'test-panel-filetree',
    type: 'board.filetree',
    title: 'File Tree',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 600),
    state: state,
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'test-panel-filetree',
      type: 'board.filetree',
      title: 'File Tree',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 600),
      state: state,
    );

void main() {
  final handler = const FileTreeCliHandler();

  group('FileTreeCliHandler — metadata', () {
    test('typeId is board.filetree', () {
      expect(handler.typeId, 'board.filetree');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(['list', 'open', 'expand', 'collapse', 'set-root', 'refresh']),
      );
    });
  });

  group('FileTreeCliHandler — list action', () {
    test('list from empty fixture returns empty fields', () async {
      final panel = _panelFromFixture('filetree_empty');
      final r = await handler.handleAction('list', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['rootPath'], '');
      expect(r.data!['selectedFile'], '');
      expect(r.data!['expandedDirs'], isEmpty);
    });

    test('list from filetree_expanded fixture returns correct data', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('list', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['rootPath'], '/Users/dev/myproject');
      expect(r.data!['selectedFile'], '/Users/dev/myproject/src/main.dart');
      final dirs = r.data!['expandedDirs'] as List;
      expect(dirs.length, 2);
      expect(dirs, contains('/Users/dev/myproject/src'));
    });
  });

  group('FileTreeCliHandler — open action', () {
    test('open with path sets selectedFile', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('open', {'path': '/Users/dev/myproject/lib/app.dart'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['selectedFile'], '/Users/dev/myproject/lib/app.dart');
    });

    test('open without path returns ok=false', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('open', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('FileTreeCliHandler — expand action', () {
    test('expand adds dir to expandedDirs', () async {
      final panel = _panelFromFixture('filetree_empty');
      final r = await handler.handleAction('expand', {'dir': '/Users/dev/src'}, panel);
      expect(r.ok, isTrue);
      final dirs = r.stateUpdate!['expandedDirs'] as List;
      expect(dirs, contains('/Users/dev/src'));
    });

    test('expand does not add duplicate dirs', () async {
      final panel = _panelFromFixture('filetree_expanded');
      // /Users/dev/myproject/src is already expanded
      final r = await handler.handleAction('expand', {'dir': '/Users/dev/myproject/src'}, panel);
      expect(r.ok, isTrue);
      final dirs = r.stateUpdate!['expandedDirs'] as List;
      final count = dirs.where((d) => d == '/Users/dev/myproject/src').length;
      expect(count, 1);
    });

    test('expand without dir returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('expand', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('FileTreeCliHandler — collapse action', () {
    test('collapse removes dir from expandedDirs', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('collapse', {'dir': '/Users/dev/myproject/src'}, panel);
      expect(r.ok, isTrue);
      final dirs = r.stateUpdate!['expandedDirs'] as List;
      expect(dirs, isNot(contains('/Users/dev/myproject/src')));
    });

    test('collapse a non-expanded dir is ok (no-op)', () async {
      final panel = _panelFromFixture('filetree_empty');
      final r = await handler.handleAction('collapse', {'dir': '/nonexistent'}, panel);
      expect(r.ok, isTrue);
    });

    test('collapse without dir returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('collapse', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('FileTreeCliHandler — set-root action', () {
    test('set-root sets rootPath and clears expandedDirs and selectedFile', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('set-root', {'path': '/Users/dev/otherproject'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['rootPath'], '/Users/dev/otherproject');
      expect(r.stateUpdate!['expandedDirs'], isEmpty);
      expect(r.stateUpdate!['selectedFile'], '');
    });

    test('set-root without path returns ok=false', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('set-root', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('FileTreeCliHandler — refresh action', () {
    test('refresh returns ok=true and stateUpdate with _refreshAt', () async {
      final panel = _panelFromFixture('filetree_expanded');
      final r = await handler.handleAction('refresh', {}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate, isNotNull);
      expect(r.stateUpdate!['_refreshAt'], isA<String>());
    });
  });

  group('FileTreeCliHandler — unknown action', () {
    test('unknown action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('delete', {}, panel);
      expect(r.ok, isFalse);
    });
  });
}
