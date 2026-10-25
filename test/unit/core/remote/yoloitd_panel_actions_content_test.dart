import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_panel_actions.dart';

RemotePanel _panel(String type, [Map<String, dynamic> state = const {}]) {
  return RemotePanel(
    id: 'p-${type.replaceAll('.', '-')}',
    type: type,
    title: type,
    bounds: const RemotePanelBounds(x: 0, y: 0, width: 320, height: 240),
    state: state,
  );
}

void main() {
  group('remote panel content projection', () {
    test('get projects every specialized panel type', () {
      final states = <String, Map<String, dynamic>>{
        'board.note.markdown': <String, dynamic>{
          'markdown': '# Notes',
          'autoHeight': true,
        },
        'board.sticky': <String, dynamic>{
          'text': 'Remember',
          'color': '#FFFFFF',
        },
        'board.shape': <String, dynamic>{
          'shape': 'diamond',
          'text': 'Decision',
        },
        'board.kanban': <String, dynamic>{
          'columns': <String>['Todo', 'Done'],
          'cards': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'card-1', 'title': 'Task'},
          ],
        },
        'board.checklist': <String, dynamic>{
          'items': <Map<String, dynamic>>[
            <String, dynamic>{'id': 'item-1', 'text': 'Check'},
          ],
        },
        'board.code.snippet': <String, dynamic>{
          'language': 'dart',
          'code': 'void main() {}',
        },
        'board.webpage': <String, dynamic>{
          'url': 'https://example.com',
          'title': 'Example',
        },
        'board.playlist': <String, dynamic>{
          'tracks': <Map<String, dynamic>>[
            <String, dynamic>{'path': '/music/a.mp3'},
          ],
          'currentIndex': 0,
        },
        'board.files': <String, dynamic>{
          'selectedPath': '/tmp/a.txt',
          'files': <Map<String, dynamic>>[
            <String, dynamic>{'path': '/tmp/a.txt'},
          ],
        },
        'board.file.preview': <String, dynamic>{'path': '/tmp/a.txt'},
        'board.filetree': <String, dynamic>{
          'rootPath': '/tmp',
          'expandedDirs': <String>['/tmp'],
        },
        'board.terminal': <String, dynamic>{
          'config': <String, dynamic>{'sessionId': 'session-1'},
        },
        'board.timer': <String, dynamic>{
          'duration': 600,
          'remaining': 300,
          'label': 'Focus',
        },
        'board.chat': <String, dynamic>{
          'configured': true,
          'messages': <Map<String, dynamic>>[
            <String, dynamic>{'role': 'user', 'text': 'Hello'},
          ],
        },
        'board.ui': <String, dynamic>{
          'tree': <String, dynamic>{'type': 'text', 'data': 'Hello UI'},
          '_lastEvent': <String, dynamic>{'type': 'tap'},
        },
        'board.custom': <String, dynamic>{'custom': 'value'},
      };
      const expectedKeys = <String, List<String>>{
        'board.note.markdown': <String>['markdown', 'autoHeight'],
        'board.sticky': <String>['text', 'color'],
        'board.shape': <String>['shape', 'fillColor', 'strokeWidth'],
        'board.kanban': <String>['columns', 'cards'],
        'board.checklist': <String>['items'],
        'board.code.snippet': <String>['language', 'code'],
        'board.webpage': <String>['url', 'title', 'favicon'],
        'board.playlist': <String>['tracks', 'currentIndex', 'playing'],
        'board.files': <String>['selectedPath', 'files'],
        'board.file.preview': <String>['path', 'filePath'],
        'board.filetree': <String>['rootPath', 'expandedDirs', 'selectedFile'],
        'board.terminal': <String>['config'],
        'board.timer': <String>['duration', 'remaining', 'label'],
        'board.chat': <String>['config', 'messages', 'configured'],
        'board.ui': <String>['tree', 'resolvedTree', 'storage', 'text'],
        'board.custom': <String>['custom'],
      };

      for (final entry in expectedKeys.entries) {
        final result = handleRemotePanelAction(
          _panel(entry.key, states[entry.key]!),
          'get',
          <String, dynamic>{},
        );
        expect(result.ok, isTrue, reason: entry.key);
        expect(result.data.keys, containsAll(entry.value), reason: entry.key);
      }

      expect(
        handleRemotePanelAction(
          _panel('board.note.markdown', states['board.note.markdown']!),
          'get',
          <String, dynamic>{},
        ).data['markdown'],
        '# Notes',
      );
      expect(
        handleRemotePanelAction(
          _panel('board.ui', states['board.ui']!),
          'get',
          <String, dynamic>{},
        ).data['lastEvent'],
        <String, dynamic>{'type': 'tap'},
      );
    });
  });

  group('board.ui remote actions', () {
    test('render normalizes a tree and resets the last event', () {
      final tree = <String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'text', 'data': 'Rendered'},
        ],
      };
      final result = handleRemotePanelAction(
        _panel('board.ui', <String, dynamic>{
          '_lastEvent': <String, dynamic>{'type': 'old'},
        }),
        'render',
        <String, dynamic>{'json': jsonEncode(tree)},
      );

      expect(result.ok, isTrue);
      expect(result.message, 'UI tree rendered');
      expect(result.stateUpdate['tree'], tree);
      expect(result.stateUpdate['_storage'], isA<Map<String, dynamic>>());
      expect(result.stateUpdate['_lastEvent'], isNull);
    });

    test('render rejects missing or invalid trees', () {
      final result = handleRemotePanelAction(
        _panel('board.ui'),
        'render',
        <String, dynamic>{'tree': 'not-json'},
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Missing or invalid'));
    });

    test('set-state merges the patch into current storage', () {
      final result = handleRemotePanelAction(
        _panel('board.ui', <String, dynamic>{
          '_storage': <String, dynamic>{'existing': 1},
        }),
        'set-state',
        <String, dynamic>{
          'state': <String, dynamic>{'added': 2},
        },
      );

      expect(result.ok, isTrue);
      expect(result.stateUpdate['_storage'], <String, dynamic>{
        'existing': 1,
        'added': 2,
      });
    });

    test('set-state rejects an invalid patch', () {
      final result = handleRemotePanelAction(
        _panel('board.ui'),
        'set-state',
        <String, dynamic>{'state': '[1,2]'},
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Missing or invalid'));
    });

    test('set-scripts merges decoded scripts into current scripts', () {
      final result = handleRemotePanelAction(
        _panel('board.ui', <String, dynamic>{
          '_scripts': <String, String>{'existing': 'old();'},
        }),
        'set-scripts',
        <String, dynamic>{'scripts': jsonEncode(<String, String>{'tap': 'go();'})},
      );

      expect(result.ok, isTrue);
      expect(result.stateUpdate['_scripts'], <String, String>{
        'existing': 'old();',
        'tap': 'go();',
      });
    });

    test('set-scripts rejects an empty or invalid patch', () {
      final result = handleRemotePanelAction(
        _panel('board.ui'),
        'set-scripts',
        <String, dynamic>{'scripts': <String, Object?>{}},
      );
      expect(result.ok, isFalse);
      expect(result.message, contains('Missing or invalid'));
    });

    test('unknown UI actions return an error', () {
      final result = handleRemotePanelAction(
        _panel('board.ui'),
        'unknown',
        <String, dynamic>{},
      );
      expect(result.ok, isFalse);
      expect(result.message, 'Unknown action: unknown');
    });
  });
}
