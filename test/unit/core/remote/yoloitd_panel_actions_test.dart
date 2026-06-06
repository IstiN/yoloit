import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';

RemotePanel _panel(String type, {Map<String, dynamic>? state}) {
  return RemotePanel(
    id: 'p1',
    type: type,
    title: 'Test',
    bounds: const RemotePanelBounds(x: 0, y: 0, width: 100, height: 100),
    state: state ?? const <String, dynamic>{},
  );
}

void main() {
  group('RemotePanelActionResult', () {
    test('toJson includes only non-empty fields', () {
      const result = RemotePanelActionResult();
      expect(result.toJson(), <String, dynamic>{'ok': true});
    });

    test('toJson includes panel when provided', () {
      final panel = _panel('board.note.markdown');
      const result = RemotePanelActionResult(
        message: 'hello',
        data: <String, dynamic>{'a': 1},
        stateUpdate: <String, dynamic>{'b': 2},
      );
      final json = result.toJson(panel: panel);
      expect(json['ok'], true);
      expect(json['message'], 'hello');
      expect(json['data'], <String, dynamic>{'a': 1});
      expect(json['stateUpdate'], <String, dynamic>{'b': 2});
      expect(json['panel'], isA<Map<String, dynamic>>());
    });
  });

  group('remotePanelActionHelp', () {
    test('returns descriptor actions and capabilities', () {
      final panel = _panel('board.terminal');
      final help = remotePanelActionHelp(panel);
      expect(help['actions'], containsAll(<String>['config', 'set-dir', 'set-session']));
      expect(help['capabilities'], isA<Map<String, dynamic>>());
    });

    test('returns fallback actions for unknown type', () {
      final panel = _panel('unknown');
      final help = remotePanelActionHelp(panel);
      expect(help['actions'], <String>['get', 'set']);
      expect(help['capabilities'], isNull);
    });
  });

  group('handleRemotePanelAction dispatch', () {
    test('get action returns content for markdown note', () {
      final panel = _panel('board.note.markdown', state: <String, dynamic>{
        'markdown': '# Hi',
        'autoHeight': true,
      });
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.ok, true);
      expect(result.data['markdown'], '# Hi');
      expect(result.data['autoHeight'], true);
    });

    test('unknown type falls back to generic set', () {
      final panel = _panel('custom');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'foo': 'bar'},
      );
      expect(result.ok, true);
      expect(result.stateUpdate['foo'], 'bar');
    });

    test('unknown action returns error', () {
      final panel = _panel('board.note.markdown');
      final result = handleRemotePanelAction(panel, 'fly', const <String, dynamic>{});
      expect(result.ok, false);
      expect(result.message, contains('Unknown'));
    });
  });

  group('markdown note', () {
    test('set updates markdown', () {
      final panel = _panel('board.note.markdown');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'text': 'hello'},
      );
      expect(result.stateUpdate['markdown'], 'hello');
    });

    test('set requires text or markdown', () {
      final panel = _panel('board.note.markdown');
      final result = handleRemotePanelAction(panel, 'set', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('append combines text', () {
      final panel = _panel('board.note.markdown', state: <String, dynamic>{
        'markdown': 'first',
      });
      final result = handleRemotePanelAction(
        panel,
        'append',
        <String, dynamic>{'text': 'second'},
      );
      expect(result.stateUpdate['markdown'], 'first\nsecond');
    });

    test('wrap toggles autoHeight', () {
      final panel = _panel('board.note.markdown');
      final wrap = handleRemotePanelAction(panel, 'wrap', const <String, dynamic>{});
      expect(wrap.stateUpdate['autoHeight'], true);
      final nowrap = handleRemotePanelAction(panel, 'nowrap', const <String, dynamic>{});
      expect(nowrap.stateUpdate['autoHeight'], false);
    });
  });

  group('sticky', () {
    test('set picks fields', () {
      final panel = _panel('board.sticky');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'text': 'hi', 'color': '#fff'},
      );
      expect(result.stateUpdate['text'], 'hi');
      expect(result.stateUpdate['color'], '#fff');
    });

    test('set requires at least one field', () {
      final panel = _panel('board.sticky');
      final result = handleRemotePanelAction(panel, 'set', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('append combines text', () {
      final panel = _panel('board.sticky', state: <String, dynamic>{
        'text': 'a',
      });
      final result = handleRemotePanelAction(
        panel,
        'append',
        <String, dynamic>{'text': 'b'},
      );
      expect(result.stateUpdate['text'], 'a\nb');
    });

    test('color updates fill and text color', () {
      final panel = _panel('board.sticky');
      final result = handleRemotePanelAction(
        panel,
        'color',
        <String, dynamic>{'color': '#000', 'textColor': '#fff', 'fontSize': 24},
      );
      expect(result.stateUpdate['color'], '#000');
      expect(result.stateUpdate['textColor'], '#fff');
      expect(result.stateUpdate['fontSize'], 24);
    });
  });

  group('shape', () {
    test('set updates fields', () {
      final panel = _panel('board.shape');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'shape': 'circle', 'text': 'Hi'},
      );
      expect(result.stateUpdate['shape'], 'circle');
      expect(result.stateUpdate['text'], 'Hi');
    });

    test('set requires fields', () {
      final panel = _panel('board.shape');
      final result = handleRemotePanelAction(panel, 'set', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('unknown action errors', () {
      final panel = _panel('board.shape');
      final result = handleRemotePanelAction(panel, 'rotate', const <String, dynamic>{});
      expect(result.ok, false);
    });
  });

  group('kanban', () {
    test('columns returns columns', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A', 'B'],
      });
      final result = handleRemotePanelAction(panel, 'columns', const <String, dynamic>{});
      expect(result.data['columns'], <String>['A', 'B']);
    });

    test('cards returns columns and cards', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
        'cards': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'title': 'T', 'columnIndex': 0},
        ],
      });
      final result = handleRemotePanelAction(panel, 'cards', const <String, dynamic>{});
      expect(result.data['columns'], <String>['A']);
      expect((result.data['cards'] as List).length, 1);
    });

    test('add-column requires name', () {
      final panel = _panel('board.kanban');
      final result = handleRemotePanelAction(panel, 'add-column', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('add-column appends column', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
      });
      final result = handleRemotePanelAction(
        panel,
        'add-column',
        <String, dynamic>{'name': 'B'},
      );
      expect(result.stateUpdate['columns'], <String>['A', 'B']);
      expect(result.data['columnIndex'], 1);
    });

    test('rename-column by index', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A', 'B'],
      });
      final result = handleRemotePanelAction(
        panel,
        'rename-column',
        <String, dynamic>{'columnId': 0, 'name': 'AA'},
      );
      expect(result.stateUpdate['columns'], <String>['AA', 'B']);
    });

    test('rename-column by name', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A', 'B'],
      });
      final result = handleRemotePanelAction(
        panel,
        'rename-column',
        <String, dynamic>{'columnId': 'b', 'name': 'BB'},
      );
      expect(result.stateUpdate['columns'], <String>['A', 'BB']);
    });

    test('remove-column shifts cards', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A', 'B'],
        'cards': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'title': 'T1', 'columnIndex': 1},
          <String, dynamic>{'id': 'c2', 'title': 'T2', 'columnIndex': 0},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'remove-column',
        <String, dynamic>{'columnId': 1},
      );
      final cards = result.stateUpdate['cards'] as List<Map<String, dynamic>>;
      expect(cards.length, 1);
      expect(cards.first['id'], 'c2');
    });

    test('add-card requires title', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
      });
      final result = handleRemotePanelAction(
        panel,
        'add-card',
        <String, dynamic>{'columnId': 'A'},
      );
      expect(result.ok, false);
    });

    test('add-card appends card', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
        'cards': <Map<String, dynamic>>[],
      });
      final result = handleRemotePanelAction(
        panel,
        'add-card',
        <String, dynamic>{'columnId': 'A', 'title': 'Task'},
      );
      final cards = result.stateUpdate['cards'] as List<Map<String, dynamic>>;
      expect(cards.length, 1);
      expect(cards.first['title'], 'Task');
      expect(result.data['cardId'], cards.first['id']);
    });

    test('move-card updates columnIndex', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A', 'B'],
        'cards': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'title': 'T', 'columnIndex': 0},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'move-card',
        <String, dynamic>{'cardId': 'c1', 'to': 1},
      );
      final cards = result.stateUpdate['cards'] as List<Map<String, dynamic>>;
      expect(cards.first['columnIndex'], 1);
    });

    test('remove-card deletes by id', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
        'cards': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'title': 'T', 'columnIndex': 0},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'remove-card',
        <String, dynamic>{'cardId': 'c1'},
      );
      final cards = result.stateUpdate['cards'] as List<Map<String, dynamic>>;
      expect(cards.isEmpty, true);
    });

    test('update-card merges fields', () {
      final panel = _panel('board.kanban', state: <String, dynamic>{
        'columns': <String>['A'],
        'cards': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'c1', 'title': 'T', 'columnIndex': 0},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'update-card',
        <String, dynamic>{'cardId': 'c1', 'title': 'Updated'},
      );
      final cards = result.stateUpdate['cards'] as List<Map<String, dynamic>>;
      expect(cards.first['title'], 'Updated');
      expect(cards.first['columnIndex'], 0);
    });
  });

  group('checklist', () {
    test('items returns items', () {
      final panel = _panel('board.checklist', state: <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'i1', 'text': 'a', 'done': false},
        ],
      });
      final result = handleRemotePanelAction(panel, 'items', const <String, dynamic>{});
      expect((result.data['items'] as List).length, 1);
    });

    test('add requires text', () {
      final panel = _panel('board.checklist');
      final result = handleRemotePanelAction(panel, 'add', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('add appends item', () {
      final panel = _panel('board.checklist');
      final result = handleRemotePanelAction(
        panel,
        'add',
        <String, dynamic>{'text': 'buy milk'},
      );
      final items = result.stateUpdate['items'] as List<Map<String, dynamic>>;
      expect(items.first['text'], 'buy milk');
      expect(items.first['done'], false);
    });

    test('check toggles done true', () {
      final panel = _panel('board.checklist', state: <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'i1', 'text': 'a', 'done': false},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'check',
        <String, dynamic>{'id': 'i1'},
      );
      expect((result.stateUpdate['items'] as List).first['done'], true);
    });

    test('uncheck toggles done false', () {
      final panel = _panel('board.checklist', state: <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'i1', 'text': 'a', 'done': true},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'uncheck',
        <String, dynamic>{'id': 'i1'},
      );
      expect((result.stateUpdate['items'] as List).first['done'], false);
    });

    test('remove deletes item', () {
      final panel = _panel('board.checklist', state: <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'i1', 'text': 'a', 'done': false},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'remove',
        <String, dynamic>{'id': 'i1'},
      );
      expect((result.stateUpdate['items'] as List).isEmpty, true);
    });

    test('rename updates text', () {
      final panel = _panel('board.checklist', state: <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'i1', 'text': 'a', 'done': false},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'rename',
        <String, dynamic>{'id': 'i1', 'text': 'b'},
      );
      expect((result.stateUpdate['items'] as List).first['text'], 'b');
    });
  });

  group('code snippet', () {
    test('set updates code and language', () {
      final panel = _panel('board.code.snippet');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'code': 'print(1)', 'language': 'python'},
      );
      expect(result.stateUpdate['code'], 'print(1)');
      expect(result.stateUpdate['language'], 'python');
    });

    test('set requires code', () {
      final panel = _panel('board.code.snippet');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'language': 'python'},
      );
      expect(result.ok, false);
    });
  });

  group('webpage', () {
    test('open requires url', () {
      final panel = _panel('board.webpage');
      final result = handleRemotePanelAction(panel, 'open', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('open sets url and title', () {
      final panel = _panel('board.webpage');
      final result = handleRemotePanelAction(
        panel,
        'open',
        <String, dynamic>{'url': 'https://example.com', 'title': 'Ex'},
      );
      expect(result.stateUpdate['url'], 'https://example.com');
      expect(result.stateUpdate['title'], 'Ex');
    });
  });

  group('playlist', () {
    test('list returns content', () {
      final panel = _panel('board.playlist', state: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'path': '/a.mp3', 'title': 'A'},
        ],
        'currentIndex': 0,
        'playing': true,
      });
      final result = handleRemotePanelAction(panel, 'list', const <String, dynamic>{});
      expect((result.data['tracks'] as List).length, 1);
      expect(result.data['playing'], true);
    });

    test('add requires path', () {
      final panel = _panel('board.playlist');
      final result = handleRemotePanelAction(panel, 'add', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('add track', () {
      final panel = _panel('board.playlist');
      final result = handleRemotePanelAction(
        panel,
        'add',
        <String, dynamic>{'path': '/a.mp3', 'title': 'A'},
      );
      final tracks = result.stateUpdate['tracks'] as List<Map<String, dynamic>>;
      expect(tracks.length, 1);
      expect(tracks.first['title'], 'A');
    });

    test('remove track', () {
      final panel = _panel('board.playlist', state: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'path': '/a.mp3', 'title': 'A'},
        ],
        'currentIndex': 0,
      });
      final result = handleRemotePanelAction(
        panel,
        'remove',
        <String, dynamic>{'index': 0},
      );
      expect((result.stateUpdate['tracks'] as List).isEmpty, true);
      expect(result.stateUpdate['currentIndex'], -1);
    });

    test('play clamps index', () {
      final panel = _panel('board.playlist', state: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'path': '/a.mp3', 'title': 'A'},
          <String, dynamic>{'path': '/b.mp3', 'title': 'B'},
        ],
        'currentIndex': 0,
      });
      final result = handleRemotePanelAction(
        panel,
        'play',
        <String, dynamic>{'index': 99},
      );
      expect(result.stateUpdate['currentIndex'], 1);
      expect(result.stateUpdate['playing'], true);
    });

    test('pause stops playing', () {
      final panel = _panel('board.playlist');
      final result = handleRemotePanelAction(panel, 'pause', const <String, dynamic>{});
      expect(result.stateUpdate['playing'], false);
    });

    test('next wraps', () {
      final panel = _panel('board.playlist', state: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'path': '/a.mp3'},
          <String, dynamic>{'path': '/b.mp3'},
        ],
        'currentIndex': 0,
      });
      final result = handleRemotePanelAction(panel, 'next', const <String, dynamic>{});
      expect(result.stateUpdate['currentIndex'], 1);
    });

    test('prev wraps to end', () {
      final panel = _panel('board.playlist', state: <String, dynamic>{
        'tracks': <Map<String, dynamic>>[
          <String, dynamic>{'path': '/a.mp3'},
          <String, dynamic>{'path': '/b.mp3'},
        ],
        'currentIndex': 0,
      });
      final result = handleRemotePanelAction(panel, 'prev', const <String, dynamic>{});
      expect(result.stateUpdate['currentIndex'], 1);
    });
  });

  group('files', () {
    test('open requires path', () {
      final panel = _panel('board.files');
      final result = handleRemotePanelAction(panel, 'open', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('open sets selectedPath', () {
      final panel = _panel('board.files');
      final result = handleRemotePanelAction(
        panel,
        'open',
        <String, dynamic>{'path': '/tmp'},
      );
      expect(result.stateUpdate['selectedPath'], '/tmp');
    });

    test('add file', () {
      final panel = _panel('board.files');
      final result = handleRemotePanelAction(
        panel,
        'add',
        <String, dynamic>{'path': '/tmp/a.txt', 'name': 'a'},
      );
      final files = result.stateUpdate['files'] as List<Map<String, dynamic>>;
      expect(files.first['path'], '/tmp/a.txt');
      expect(files.first['name'], 'a');
    });

    test('remove by id', () {
      final panel = _panel('board.files', state: <String, dynamic>{
        'files': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'f1', 'path': '/tmp/a.txt', 'name': 'a'},
        ],
      });
      final result = handleRemotePanelAction(
        panel,
        'remove',
        <String, dynamic>{'id': 'f1'},
      );
      expect((result.stateUpdate['files'] as List).isEmpty, true);
    });

    test('clear empties files', () {
      final panel = _panel('board.files', state: <String, dynamic>{
        'files': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'f1', 'path': '/tmp/a.txt'},
        ],
      });
      final result = handleRemotePanelAction(panel, 'clear', const <String, dynamic>{});
      expect((result.stateUpdate['files'] as List).isEmpty, true);
    });
  });

  group('file preview', () {
    test('open requires path', () {
      final panel = _panel('board.file.preview');
      final result = handleRemotePanelAction(panel, 'open', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('open sets both path fields', () {
      final panel = _panel('board.file.preview');
      final result = handleRemotePanelAction(
        panel,
        'open',
        <String, dynamic>{'path': '/tmp/a.txt', 'title': 'A'},
      );
      expect(result.stateUpdate['path'], '/tmp/a.txt');
      expect(result.stateUpdate['filePath'], '/tmp/a.txt');
      expect(result.stateUpdate['title'], 'A');
    });
  });

  group('file tree', () {
    test('list returns content', () {
      final panel = _panel('board.filetree', state: <String, dynamic>{
        'rootPath': '/tmp',
        'expandedDirs': <String>[],
        'selectedFile': '',
      });
      final result = handleRemotePanelAction(panel, 'list', const <String, dynamic>{});
      expect(result.data['rootPath'], '/tmp');
    });

    test('open sets selectedFile', () {
      final panel = _panel('board.filetree');
      final result = handleRemotePanelAction(
        panel,
        'open',
        <String, dynamic>{'path': '/tmp/a.txt'},
      );
      expect(result.stateUpdate['selectedFile'], '/tmp/a.txt');
    });

    test('expand adds dir', () {
      final panel = _panel('board.filetree');
      final result = handleRemotePanelAction(
        panel,
        'expand',
        <String, dynamic>{'dir': '/tmp'},
      );
      expect((result.stateUpdate['expandedDirs'] as List).single, '/tmp');
    });

    test('expand does not duplicate', () {
      final panel = _panel('board.filetree', state: <String, dynamic>{
        'expandedDirs': <String>['/tmp'],
      });
      final result = handleRemotePanelAction(
        panel,
        'expand',
        <String, dynamic>{'dir': '/tmp'},
      );
      expect((result.stateUpdate['expandedDirs'] as List).length, 1);
    });

    test('collapse removes dir', () {
      final panel = _panel('board.filetree', state: <String, dynamic>{
        'expandedDirs': <String>['/tmp'],
      });
      final result = handleRemotePanelAction(
        panel,
        'collapse',
        <String, dynamic>{'dir': '/tmp'},
      );
      expect((result.stateUpdate['expandedDirs'] as List).isEmpty, true);
    });

    test('set-root resets expanded and selected', () {
      final panel = _panel('board.filetree', state: <String, dynamic>{
        'rootPath': '/old',
        'expandedDirs': <String>['/old/a'],
        'selectedFile': '/old/a/x',
      });
      final result = handleRemotePanelAction(
        panel,
        'set-root',
        <String, dynamic>{'path': '/new'},
      );
      expect(result.stateUpdate['rootPath'], '/new');
      expect((result.stateUpdate['expandedDirs'] as List).isEmpty, true);
      expect(result.stateUpdate['selectedFile'], '');
    });

    test('refresh sets _refreshAt', () {
      final panel = _panel('board.filetree');
      final result = handleRemotePanelAction(panel, 'refresh', const <String, dynamic>{});
      expect(result.stateUpdate.containsKey('_refreshAt'), true);
    });
  });

  group('terminal', () {
    test('config returns current config', () {
      final panel = _panel('board.terminal', state: <String, dynamic>{
        'config': <String, dynamic>{'sessionId': 's1', 'workingDir': '/tmp'},
      });
      final result = handleRemotePanelAction(panel, 'config', const <String, dynamic>{});
      expect((result.data['config'] as Map)['sessionId'], 's1');
    });

    test('set-dir requires dir', () {
      final panel = _panel('board.terminal');
      final result = handleRemotePanelAction(panel, 'set-dir', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('set-dir updates workingDir', () {
      final panel = _panel('board.terminal', state: <String, dynamic>{
        'config': <String, dynamic>{'sessionId': 's1'},
      });
      final result = handleRemotePanelAction(
        panel,
        'set-dir',
        <String, dynamic>{'dir': '/new'},
      );
      expect((result.stateUpdate['config'] as Map)['workingDir'], '/new');
    });

    test('set-session requires id', () {
      final panel = _panel('board.terminal');
      final result = handleRemotePanelAction(
        panel,
        'set-session',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-session updates sessionId', () {
      final panel = _panel('board.terminal');
      final result = handleRemotePanelAction(
        panel,
        'set-session',
        <String, dynamic>{'sessionId': 's2'},
      );
      expect((result.stateUpdate['config'] as Map)['sessionId'], 's2');
    });
  });

  group('timer', () {
    test('status returns content', () {
      final panel = _panel('board.timer', state: <String, dynamic>{
        'duration': 60,
        'remaining': 30,
        'isRunning': true,
      });
      final result = handleRemotePanelAction(panel, 'status', const <String, dynamic>{});
      expect(result.data['duration'], 60);
      expect(result.data['remaining'], 30);
    });

    test('set resets timer with clamped duration', () {
      final panel = _panel('board.timer');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'duration': 0, 'label': 'Pomodoro'},
      );
      expect(result.stateUpdate['duration'], 1);
      expect(result.stateUpdate['remaining'], 1);
      expect(result.stateUpdate['isRunning'], false);
      expect(result.stateUpdate['label'], 'Pomodoro');
    });

    test('start sets running and lastTick', () {
      final panel = _panel('board.timer');
      final result = handleRemotePanelAction(
        panel,
        'start',
        <String, dynamic>{'duration': 120},
      );
      expect(result.stateUpdate['duration'], 120);
      expect(result.stateUpdate['isRunning'], true);
      expect(result.stateUpdate['lastTick'], isA<int>());
    });

    test('pause stops running', () {
      final panel = _panel('board.timer');
      final result = handleRemotePanelAction(panel, 'pause', const <String, dynamic>{});
      expect(result.stateUpdate['isRunning'], false);
      expect(result.stateUpdate['isPaused'], true);
    });

    test('resume resets lastTick', () {
      final panel = _panel('board.timer');
      final result = handleRemotePanelAction(panel, 'resume', const <String, dynamic>{});
      expect(result.stateUpdate['isRunning'], true);
      expect(result.stateUpdate['isPaused'], false);
      expect(result.stateUpdate['lastTick'], isA<int>());
    });

    test('reset uses stored duration', () {
      final panel = _panel('board.timer', state: <String, dynamic>{
        'duration': 300,
        'remaining': 10,
        'isRunning': true,
      });
      final result = handleRemotePanelAction(panel, 'reset', const <String, dynamic>{});
      expect(result.stateUpdate['remaining'], 300);
      expect(result.stateUpdate['isRunning'], false);
    });
  });

  group('chat', () {
    test('messages returns total', () {
      final panel = _panel('board.chat', state: <String, dynamic>{
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hi'},
        ],
      });
      final result = handleRemotePanelAction(panel, 'messages', const <String, dynamic>{});
      expect((result.data['messages'] as List).length, 1);
      expect(result.data['total'], 1);
    });

    test('send requires text', () {
      final panel = _panel('board.chat');
      final result = handleRemotePanelAction(panel, 'send', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('send appends user message', () {
      final panel = _panel('board.chat');
      final result = handleRemotePanelAction(
        panel,
        'send',
        <String, dynamic>{'text': 'hello'},
      );
      final messages = result.stateUpdate['messages'] as List<Map<String, dynamic>>;
      expect(messages.first['role'], 'user');
      expect(messages.first['content'], 'hello');
      expect(result.stateUpdate['configured'], true);
    });

    test('config merges settings', () {
      final panel = _panel('board.chat', state: <String, dynamic>{
        'config': <String, dynamic>{'provider': 'openai'},
      });
      final result = handleRemotePanelAction(
        panel,
        'config',
        <String, dynamic>{'config': <String, dynamic>{'model': 'gpt-4'}},
      );
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['provider'], 'openai');
      expect(config['model'], 'gpt-4');
      expect(result.data['config'], config);
    });

    test('clear empties messages', () {
      final panel = _panel('board.chat', state: <String, dynamic>{
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hi'},
        ],
      });
      final result = handleRemotePanelAction(panel, 'clear', const <String, dynamic>{});
      expect((result.stateUpdate['messages'] as List).isEmpty, true);
    });

    test('status returns count', () {
      final panel = _panel('board.chat', state: <String, dynamic>{
        'messages': <Map<String, dynamic>>[
          <String, dynamic>{'role': 'user', 'content': 'hi'},
        ],
      });
      final result = handleRemotePanelAction(panel, 'status', const <String, dynamic>{});
      expect(result.data['messageCount'], 1);
      expect(result.data['isProcessing'], false);
    });
  });

  group('setup guide', () {
    test('select adds package id', () {
      final panel = _panel('board.setup_guide');
      final result = handleRemotePanelAction(
        panel,
        'select',
        <String, dynamic>{'packageId': 'node'},
      );
      expect((result.stateUpdate['selectedPackageIds'] as List).single, 'node');
    });

    test('unselect removes package id', () {
      final panel = _panel('board.setup_guide', state: <String, dynamic>{
        'selectedPackageIds': <String>['node'],
      });
      final result = handleRemotePanelAction(
        panel,
        'unselect',
        <String, dynamic>{'packageId': 'node'},
      );
      expect((result.stateUpdate['selectedPackageIds'] as List).isEmpty, true);
    });

    test('set-selected replaces list', () {
      final panel = _panel('board.setup_guide');
      final result = handleRemotePanelAction(
        panel,
        'set-selected',
        <String, dynamic>{'packageIds': <String>['a', 'b']},
      );
      expect(result.stateUpdate['selectedPackageIds'], <String>['a', 'b']);
    });
  });

  group('run', () {
    test('get returns state copy', () {
      final panel = _panel('board.run', state: <String, dynamic>{
        'group': 'default',
      });
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['group'], 'default');
    });

    test('set-group requires group', () {
      final panel = _panel('board.run');
      final result = handleRemotePanelAction(
        panel,
        'set-group',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-group updates group', () {
      final panel = _panel('board.run');
      final result = handleRemotePanelAction(
        panel,
        'set-group',
        <String, dynamic>{'group': 'prod'},
      );
      expect(result.stateUpdate['group'], 'prod');
    });

    test('select-session requires id', () {
      final panel = _panel('board.run');
      final result = handleRemotePanelAction(
        panel,
        'select-session',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('select-session updates activeSessionId', () {
      final panel = _panel('board.run');
      final result = handleRemotePanelAction(
        panel,
        'select-session',
        <String, dynamic>{'sessionId': 's1'},
      );
      expect(result.stateUpdate['activeSessionId'], 's1');
    });

    test('clear-session nulls activeSessionId', () {
      final panel = _panel('board.run');
      final result = handleRemotePanelAction(
        panel,
        'clear-session',
        const <String, dynamic>{},
      );
      expect(result.stateUpdate['activeSessionId'], isNull);
    });

    test('run_configs dispatches same handler', () {
      final panel = _panel('board.run_configs', state: <String, dynamic>{
        'group': 'x',
      });
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['group'], 'x');
    });
  });

  group('diff preview', () {
    test('open requires path', () {
      final panel = _panel('board.diff.preview');
      final result = handleRemotePanelAction(panel, 'open', const <String, dynamic>{});
      expect(result.ok, false);
    });

    test('open sets filePath and title', () {
      final panel = _panel('board.diff.preview');
      final result = handleRemotePanelAction(
        panel,
        'open',
        <String, dynamic>{'path': '/a.diff', 'title': 'Diff'},
      );
      expect(result.stateUpdate['filePath'], '/a.diff');
      expect(result.stateUpdate['title'], 'Diff');
    });

    test('set-root requires rootPath', () {
      final panel = _panel('board.diff.preview');
      final result = handleRemotePanelAction(
        panel,
        'set-root',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-root updates rootPath', () {
      final panel = _panel('board.diff.preview');
      final result = handleRemotePanelAction(
        panel,
        'set-root',
        <String, dynamic>{'rootPath': '/repo'},
      );
      expect(result.stateUpdate['rootPath'], '/repo');
    });
  });

  group('yolo assistant', () {
    test('get returns state', () {
      final panel = _panel('board.yolo_assistant', state: <String, dynamic>{
        'mode': 'chat',
      });
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['mode'], 'chat');
    });

    test('set-mode requires mode', () {
      final panel = _panel('board.yolo_assistant');
      final result = handleRemotePanelAction(
        panel,
        'set-mode',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-mode updates mode', () {
      final panel = _panel('board.yolo_assistant');
      final result = handleRemotePanelAction(
        panel,
        'set-mode',
        <String, dynamic>{'mode': 'voice'},
      );
      expect(result.stateUpdate['mode'], 'voice');
    });

    test('set-status requires status', () {
      final panel = _panel('board.yolo_assistant');
      final result = handleRemotePanelAction(
        panel,
        'set-status',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-status updates assistantStatus', () {
      final panel = _panel('board.yolo_assistant');
      final result = handleRemotePanelAction(
        panel,
        'set-status',
        <String, dynamic>{'status': 'listening'},
      );
      expect(result.stateUpdate['assistantStatus'], 'listening');
    });

    test('clear resets messages and voice fields', () {
      final panel = _panel('board.yolo_assistant');
      final result = handleRemotePanelAction(panel, 'clear', const <String, dynamic>{});
      expect((result.stateUpdate['messages'] as List).isEmpty, true);
      expect(result.stateUpdate['voiceDraft'], '');
      expect(result.stateUpdate['voiceResponse'], '');
    });
  });

  group('custom widget', () {
    test('get returns state', () {
      final panel = _panel('board.widget.custom', state: <String, dynamic>{
        'widgetId': 'w1',
      });
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['widgetId'], 'w1');
    });

    test('set-widget requires widgetId', () {
      final panel = _panel('board.widget.custom');
      final result = handleRemotePanelAction(
        panel,
        'set-widget',
        const <String, dynamic>{},
      );
      expect(result.ok, false);
    });

    test('set-widget updates widgetId', () {
      final panel = _panel('board.widget.custom');
      final result = handleRemotePanelAction(
        panel,
        'set-widget',
        <String, dynamic>{'widgetId': 'w2'},
      );
      expect(result.stateUpdate['widgetId'], 'w2');
    });

    test('set-config merges config', () {
      final panel = _panel('board.widget.custom', state: <String, dynamic>{
        'config': <String, dynamic>{'a': 1},
      });
      final result = handleRemotePanelAction(
        panel,
        'set-config',
        <String, dynamic>{'config': <String, dynamic>{'b': 2}},
      );
      final config = result.stateUpdate['config'] as Map<String, dynamic>;
      expect(config['a'], 1);
      expect(config['b'], 2);
    });

    test('set strips action and applies args', () {
      final panel = _panel('board.widget.custom');
      final result = handleRemotePanelAction(
        panel,
        'set',
        <String, dynamic>{'action': 'set', 'foo': 'bar'},
      );
      expect(result.stateUpdate['foo'], 'bar');
      expect(result.stateUpdate.containsKey('action'), false);
    });
  });

  group('_content defaults', () {
    test('unknown panel returns full state', () {
      final panel = _panel('weird', state: <String, dynamic>{'a': 1});
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['a'], 1);
    });

    test('kanban defaults columns', () {
      final panel = _panel('board.kanban');
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['columns'], <String>['Todo', 'Doing', 'Done']);
    });

    test('timer defaults duration', () {
      final panel = _panel('board.timer');
      final result = handleRemotePanelAction(panel, 'get', const <String, dynamic>{});
      expect(result.data['duration'], 300);
      expect(result.data['remaining'], 300);
    });
  });
}
