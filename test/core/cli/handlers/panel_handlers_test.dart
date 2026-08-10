// covers-write: board.webpage, board.playlist, board.checklist, board.code.snippet, board.files, board.file.preview, board.sticky, board.shape, board.terminal
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/cli/handlers/webpage_handler.dart';
import 'package:yoloit/core/cli/handlers/playlist_handler.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/core/cli/handlers/files_handler.dart';
import 'package:yoloit/core/cli/handlers/shape_handler.dart';
import 'package:yoloit/core/cli/handlers/sticky_note_handler.dart';
import 'package:yoloit/core/cli/handlers/terminal_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/webview_manager.dart';

BoardPanelInstance _panel(
  String type, {
  Map<String, dynamic> state = const {},
}) => BoardPanelInstance(
  id: 'p1',
  type: type,
  title: 'Test',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
  state: state,
);

void main() {
  group('WebpageCliHandler', () {
    final h = const WebpageCliHandler();

    test('open sets URL', () async {
      final r = await h.handleAction('open', {
        'url': 'https://x.com',
      }, _panel('board.webpage'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['url'], 'https://x.com');
    });

    test('get returns URL', () async {
      final r = await h.handleAction(
        'get',
        {},
        _panel('board.webpage', state: {'url': 'https://a.com'}),
      );
      expect(r.data!['url'], 'https://a.com');
    });

    test('open requires url', () async {
      final r = await h.handleAction('open', {}, _panel('board.webpage'));
      expect(r.ok, isFalse);
    });
  });

  group('WebpageCliHandler webview actions', () {
    final h = const WebpageCliHandler();
    final manager = WebViewManager.instance;

    tearDown(() => manager.remove('p1'));

    void registerEntry({
      Future<void> Function(String js)? onRun,
      Future<Object?> Function(String js)? onRunResult,
    }) {
      manager.registerEntry(
        'p1',
        WebViewEntry(
          runJavaScript: onRun,
          runJavaScriptReturningResult: onRunResult,
        ),
      );
    }

    test('click requires a selector', () async {
      final r = await h.handleAction('click', {}, _panel('board.webpage'));
      expect(r.ok, isFalse);
      expect(r.message, 'Missing selector parameter');
    });

    test('click fails when the webview is not initialized', () async {
      final r = await h.handleAction('click', {
        'selector': '#btn',
      }, _panel('board.webpage'));
      expect(r.ok, isFalse);
      expect(r.message, 'WebView is not initialized for this panel');
    });

    test('click runs JS and reports the clicked selector', () async {
      String? captured;
      registerEntry(onRunResult: (js) async {
        captured = js;
        return true;
      });

      final r = await h.handleAction('click', {
        'selector': '#btn',
      }, _panel('board.webpage'));

      expect(r.ok, isTrue);
      expect(r.message, 'Clicked #btn');
      expect(r.data, {'selector': '#btn'});
      expect(captured, contains('document.querySelector("#btn")'));
    });

    test('click treats a truthy string result as success', () async {
      registerEntry(onRunResult: (js) async => 'true');

      final r = await h.handleAction('click', {
        'selector': '.link',
      }, _panel('board.webpage'));

      expect(r.ok, isTrue);
      expect(r.message, 'Clicked .link');
    });

    test('click fails when no element matches', () async {
      registerEntry(onRunResult: (js) async => false);

      final r = await h.handleAction('click', {
        'selector': '#nope',
      }, _panel('board.webpage'));

      expect(r.ok, isFalse);
      expect(r.message, 'No element matched selector: #nope');
    });

    test('click reports webview errors', () async {
      registerEntry(onRunResult: (js) async => throw StateError('boom'));

      final r = await h.handleAction('click', {
        'selector': '#btn',
      }, _panel('board.webpage'));

      expect(r.ok, isFalse);
      expect(r.message, contains('WebView action failed'));
    });

    test('scroll uses window.scrollTo by default', () async {
      String? captured;
      registerEntry(onRun: (js) async => captured = js);

      final r = await h.handleAction('scroll', {
        'x': 10,
        'y': 20.5,
      }, _panel('board.webpage'));

      expect(r.ok, isTrue);
      expect(r.message, 'Scrolled to (10.0, 20.5)');
      expect(r.data, {'x': 10.0, 'y': 20.5, 'by': false});
      expect(captured, 'window.scrollTo(10, 20.5);');
    });

    test('scroll uses window.scrollBy in by mode', () async {
      String? captured;
      registerEntry(onRun: (js) async => captured = js);

      final r = await h.handleAction('scroll', {
        'x': 0,
        'y': 100,
        'by': true,
      }, _panel('board.webpage'));

      expect(r.ok, isTrue);
      expect(r.message, 'Scrolled by (0.0, 100.0)');
      expect(captured, 'window.scrollBy(0, 100);');
    });

    test('scroll parses string coordinates with fallback', () async {
      String? captured;
      registerEntry(onRun: (js) async => captured = js);

      final r = await h.handleAction('scroll', {
        'x': '15',
        'y': 'abc',
      }, _panel('board.webpage'));

      expect(r.ok, isTrue);
      expect(captured, 'window.scrollTo(15, 0);');
    });

    test('scroll fails when the webview is not initialized', () async {
      final r = await h.handleAction('scroll', {
        'y': 10,
      }, _panel('board.webpage'));
      expect(r.ok, isFalse);
      expect(r.message, 'WebView is not initialized for this panel');
    });
  });

  group('PlaylistCliHandler', () {
    final h = const PlaylistCliHandler();

    test('add track', () async {
      final r = await h.handleAction('add', {
        'path': '/music/a.mp3',
      }, _panel('board.playlist'));
      expect(r.ok, isTrue);
      expect((r.stateUpdate!['tracks'] as List).length, 1);
    });

    test('play', () async {
      final p = _panel(
        'board.playlist',
        state: {
          'tracks': [
            {'path': '/a.mp3', 'title': 'a'},
          ],
        },
      );
      final r = await h.handleAction('play', {'index': 0}, p);
      expect(r.stateUpdate!['playing'], true);
      expect(r.stateUpdate!['currentIndex'], 0);
    });

    test('pause', () async {
      final r = await h.handleAction(
        'pause',
        {},
        _panel('board.playlist', state: {'playing': true}),
      );
      expect(r.stateUpdate!['playing'], false);
    });

    test('remove', () async {
      final p = _panel(
        'board.playlist',
        state: {
          'tracks': [
            {'path': '/a.mp3', 'title': 'a'},
          ],
        },
      );
      final r = await h.handleAction('remove', {'index': 0}, p);
      expect((r.stateUpdate!['tracks'] as List), isEmpty);
    });

    test('list returns playlist', () async {
      final r = await h.handleAction('list', {}, _panel('board.playlist'));
      expect(r.ok, isTrue);
      expect(r.data!['tracks'], isA<List>());
    });
  });

  group('ChecklistCliHandler', () {
    final h = const ChecklistCliHandler();

    test('add item', () async {
      final r = await h.handleAction('add', {
        'text': 'Buy milk',
      }, _panel('board.checklist'));
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 1);
      expect(items[0]['text'], 'Buy milk');
      expect(items[0]['done'], false);
    });

    test('check item', () async {
      final p = _panel(
        'board.checklist',
        state: {
          'items': [
            {'text': 'A', 'checked': false},
          ],
        },
      );
      final r = await h.handleAction('check', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List)[0]['done'], true);
    });

    test('uncheck item', () async {
      final p = _panel(
        'board.checklist',
        state: {
          'items': [
            {'text': 'A', 'checked': true},
          ],
        },
      );
      final r = await h.handleAction('uncheck', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List)[0]['done'], false);
    });

    test('remove item', () async {
      final p = _panel(
        'board.checklist',
        state: {
          'items': [
            {'text': 'A', 'checked': false},
          ],
        },
      );
      final r = await h.handleAction('remove', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List), isEmpty);
    });

    test('rename item', () async {
      final p = _panel(
        'board.checklist',
        state: {
          'items': [
            {'text': 'Old', 'checked': false},
          ],
        },
      );
      final r = await h.handleAction(
        'rename',
        {'index': 0, 'newText': 'New'},
        p,
      );
      expect((r.stateUpdate!['items'] as List)[0]['text'], 'New');
    });
  });

  group('CodeSnippetCliHandler', () {
    final h = const CodeSnippetCliHandler();

    test('set code', () async {
      final r = await h.handleAction('set', {
        'code': 'print("hi")',
        'language': 'python',
      }, _panel('board.code.snippet'));
      expect(r.stateUpdate!['code'], 'print("hi")');
      expect(r.stateUpdate!['language'], 'python');
    });

    test('get code', () async {
      final p = _panel(
        'board.code.snippet',
        state: {'code': 'x=1', 'language': 'python'},
      );
      final r = await h.handleAction('get', {}, p);
      expect(r.data!['code'], 'x=1');
      expect(r.data!['language'], 'python');
    });

    test('set requires code', () async {
      final r = await h.handleAction('set', {}, _panel('board.code.snippet'));
      expect(r.ok, isFalse);
    });
  });

  group('FilesCliHandler', () {
    final h = const FilesCliHandler();

    test('open sets path', () async {
      final r = await h.handleAction('open', {
        'path': '/home',
      }, _panel('board.files'));
      expect(r.stateUpdate!['selectedPath'], '/home');
    });

    test('get returns path and files', () async {
      final p = _panel('board.files', state: {
        'selectedPath': '/docs',
        'files': [
          {'id': '1', 'path': '/docs/a.txt', 'name': 'a.txt'},
        ],
      });
      final r = await h.handleAction('get', {}, p);
      expect(r.data!['selectedPath'], '/docs');
      expect((r.data!['files'] as List).length, 1);
    });

    test('add and remove file entries', () async {
      final add = await h.handleAction('add', {
        'path': '/tmp/demo.pdf',
      }, _panel('board.files'));
      expect(add.ok, isTrue);
      final files = add.stateUpdate!['files'] as List;
      expect(files.length, 1);

      final remove = await h.handleAction('remove', {
        'path': '/tmp/demo.pdf',
      }, _panel('board.files', state: {'files': files}));
      expect(remove.ok, isTrue);
      expect((remove.stateUpdate!['files'] as List), isEmpty);
    });
  });

  group('FilePreviewCliHandler', () {
    final h = const FilePreviewCliHandler();

    test('open sets file', () async {
      final r = await h.handleAction('open', {
        'path': '/img.png',
      }, _panel('board.file.preview'));
      expect(r.stateUpdate!['path'], '/img.png');
      expect(r.stateUpdate!['filePath'], '/img.png');
    });

    test('get returns file', () async {
      final p = _panel('board.file.preview', state: {'path': '/img.png'});
      final r = await h.handleAction('get', {}, p);
      expect(r.data!['path'], '/img.png');
      expect(r.data!['filePath'], '/img.png');
    });
  });

  group('StickyNoteCliHandler', () {
    final h = const StickyNoteCliHandler();

    test('set updates text', () async {
      final r = await h.handleAction('set', {
        'text': 'idea',
      }, _panel('board.sticky'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['text'], 'idea');
    });

    test('set updates appearance fields', () async {
      final r = await h.handleAction('set', {
        'color': '#FDE68A',
        'textColor': '#111827',
        'fontSize': 24,
      }, _panel('board.sticky'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['color'], '#FDE68A');
      expect(r.stateUpdate!['textColor'], '#111827');
      expect(r.stateUpdate!['fontSize'], 24);
    });

    test('append preserves current text', () async {
      final p = _panel('board.sticky', state: {'text': 'a'});
      final r = await h.handleAction('append', {'text': 'b'}, p);
      expect(r.stateUpdate!['text'], 'a\nb');
    });

    test('append resolves yoloit_clip text file path', () async {
      final clipDir = Directory('${PlatformDirs.instance.tempDir}/yoloit_clip');
      await clipDir.create(recursive: true);
      final clip = File('${clipDir.path}/clip_1782467512509.txt');
      await clip.writeAsString('Sticky body');
      addTearDown(() async {
        if (await clip.exists()) await clip.delete();
      });

      final r = await h.handleAction('append', {
        'text': clip.path,
      }, _panel('board.sticky', state: {'text': 'a'}));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['text'], 'a\nSticky body');
    });
  });

  group('ShapeCliHandler', () {
    final h = const ShapeCliHandler();

    test('set resolves yoloit_clip text file path', () async {
      final clipDir = Directory('${PlatformDirs.instance.tempDir}/yoloit_clip');
      await clipDir.create(recursive: true);
      final clip = File('${clipDir.path}/clip_1782422417319.txt');
      await clip.writeAsString('Effort →');
      addTearDown(() async {
        if (await clip.exists()) await clip.delete();
      });

      final r = await h.handleAction('set', {
        'text': clip.path,
      }, _panel('board.shape'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['text'], 'Effort →');
    });

    test('set updates shape fields', () async {
      final r = await h.handleAction('set', {
        'shape': 'diamond',
        'text': 'Decision',
        'strokeColor': '#fff',
        'fillColor': '#00000000',
        'textColor': '#E2E8F0',
        'strokeWidth': 4,
        'textHAlign': 'right',
        'textVAlign': 'bottom',
        'textOrientation': 'vertical',
      }, _panel('board.shape'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['shape'], 'diamond');
      expect(r.stateUpdate!['text'], 'Decision');
      expect(r.stateUpdate!['fillColor'], '#00000000');
      expect(r.stateUpdate!['textColor'], '#E2E8F0');
      expect(r.stateUpdate!['strokeWidth'], 4);
      expect(r.stateUpdate!['textHAlign'], 'right');
      expect(r.stateUpdate!['textVAlign'], 'bottom');
      expect(r.stateUpdate!['textOrientation'], 'vertical');
    });

    test('set unwraps literal shell quotes from text', () async {
      final r = await h.handleAction('set', {
        'text': "'Impact ↑'",
        'fillColor': '"#FF0000"',
        'strokeColor': '"#0000FF"',
      }, _panel('board.shape'));

      expect(r.ok, isTrue);
      expect(r.stateUpdate!['text'], 'Impact ↑');
      expect(r.stateUpdate!['fillColor'], '#FF0000');
      expect(r.stateUpdate!['strokeColor'], '#0000FF');
    });

    test('set coerces quoted strokeWidth strings to numbers', () async {
      final r = await h.handleAction('set', {
        'strokeWidth': '"2"',
      }, _panel('board.shape'));

      expect(r.ok, isTrue);
      expect(r.stateUpdate!['strokeWidth'], 2);
    });
  });

  group('TerminalCliHandler', () {
    final h = const TerminalCliHandler();

    test('set-dir sets working directory', () async {
      final r = await h.handleAction('set-dir', {
        'dir': '/home',
      }, _panel('board.terminal'));
      expect(r.stateUpdate!['config']['workingDir'], '/home');
    });

    test('config returns config', () async {
      final p = _panel(
        'board.terminal',
        state: {
          'config': {'workingDir': '/tmp'},
        },
      );
      final r = await h.handleAction('config', {}, p);
      expect(r.data!['config']['workingDir'], '/tmp');
    });
  });
}
