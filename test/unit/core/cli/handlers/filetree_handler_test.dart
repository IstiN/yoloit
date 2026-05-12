import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/filetree_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'p1',
      type: 'board.filetree',
      title: 'File Tree',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 500),
      state: state,
    );

void main() {
  final handler = const FileTreeCliHandler();

  test('typeId matches', () {
    expect(handler.typeId, 'board.filetree');
  });

  test('supportedActions contains expected actions', () {
    expect(
      handler.supportedActions,
      containsAll([
        'list',
        'open',
        'expand',
        'collapse',
        'set-root',
        'refresh',
      ]),
    );
  });

  group('getContent', () {
    test('returns correct structure with defaults', () {
      final content = handler.getContent(_panel());
      expect(content['rootPath'], '');
      expect(content['expandedDirs'], <String>[]);
      expect(content['selectedFile'], '');
    });

    test('returns populated state', () {
      final panel = _panel(
        state: {
          'rootPath': '/home/user/project',
          'expandedDirs': ['src', 'lib'],
          'selectedFile': 'main.dart',
        },
      );
      final content = handler.getContent(panel);
      expect(content['rootPath'], '/home/user/project');
      expect(content['expandedDirs'], ['src', 'lib']);
      expect(content['selectedFile'], 'main.dart');
    });
  });

  group('handleAction', () {
    test('set-root updates rootPath and resets state', () async {
      final r = await handler.handleAction('set-root', {
        'path': '/new/root',
      }, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['rootPath'], '/new/root');
      expect(r.stateUpdate!['expandedDirs'], <String>[]);
      expect(r.stateUpdate!['selectedFile'], '');
    });

    test('set-root without path returns error', () async {
      final r = await handler.handleAction('set-root', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('expand adds dir to expandedDirs', () async {
      final panel = _panel(
        state: {
          'expandedDirs': ['src'],
        },
      );
      final r = await handler.handleAction('expand', {'dir': 'lib'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['expandedDirs'], contains('lib'));
      expect(r.stateUpdate!['expandedDirs'], contains('src'));
    });

    test('expand does not duplicate existing dir', () async {
      final panel = _panel(
        state: {
          'expandedDirs': ['src'],
        },
      );
      final r = await handler.handleAction('expand', {'dir': 'src'}, panel);
      expect(r.ok, isTrue);
      final dirs = r.stateUpdate!['expandedDirs'] as List;
      expect(dirs.where((d) => d == 'src').length, 1);
    });

    test('expand without dir returns error', () async {
      final r = await handler.handleAction('expand', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('collapse removes dir from expandedDirs', () async {
      final panel = _panel(
        state: {
          'expandedDirs': ['src', 'lib'],
        },
      );
      final r = await handler.handleAction('collapse', {'dir': 'src'}, panel);
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['expandedDirs'], isNot(contains('src')));
      expect(r.stateUpdate!['expandedDirs'], contains('lib'));
    });

    test('collapse without dir returns error', () async {
      final r = await handler.handleAction('collapse', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('open sets selectedFile', () async {
      final r = await handler.handleAction('open', {
        'path': 'main.dart',
      }, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['selectedFile'], 'main.dart');
    });

    test('open without path returns error', () async {
      final r = await handler.handleAction('open', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Missing'));
    });

    test('list returns getContent data', () async {
      final panel = _panel(state: {'rootPath': '/root'});
      final r = await handler.handleAction('list', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['rootPath'], '/root');
    });

    test('refresh updates _refreshAt', () async {
      final r = await handler.handleAction('refresh', {}, _panel());
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['_refreshAt'], isNotNull);
    });

    test('unknown action returns error', () async {
      final r = await handler.handleAction('unknown', {}, _panel());
      expect(r.ok, isFalse);
      expect(r.message, contains('Unknown'));
    });
  });
}
