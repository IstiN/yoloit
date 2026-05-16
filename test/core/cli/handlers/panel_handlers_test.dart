import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/webpage_handler.dart';
import 'package:yoloit/core/cli/handlers/playlist_handler.dart';
import 'package:yoloit/core/cli/handlers/checklist_handler.dart';
import 'package:yoloit/core/cli/handlers/code_snippet_handler.dart';
import 'package:yoloit/core/cli/handlers/files_handler.dart';
import 'package:yoloit/core/cli/handlers/terminal_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

BoardPanelInstance _panel(String type, {Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
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
      final r = await h.handleAction('open', {'url': 'https://x.com'}, _panel('board.webpage'));
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['url'], 'https://x.com');
    });

    test('get returns URL', () async {
      final r = await h.handleAction(
          'get', {}, _panel('board.webpage', state: {'url': 'https://a.com'}));
      expect(r.data!['url'], 'https://a.com');
    });

    test('open requires url', () async {
      final r = await h.handleAction('open', {}, _panel('board.webpage'));
      expect(r.ok, isFalse);
    });
  });

  group('PlaylistCliHandler', () {
    final h = const PlaylistCliHandler();

    test('add track', () async {
      final r = await h.handleAction('add', {'path': '/music/a.mp3'}, _panel('board.playlist'));
      expect(r.ok, isTrue);
      expect((r.stateUpdate!['playlist'] as List).length, 1);
    });

    test('play', () async {
      final p = _panel('board.playlist', state: {
        'playlist': [{'path': '/a.mp3', 'title': 'a'}]
      });
      final r = await h.handleAction('play', {'index': 0}, p);
      expect(r.stateUpdate!['playing'], true);
      expect(r.stateUpdate!['currentIndex'], 0);
    });

    test('pause', () async {
      final r = await h.handleAction('pause', {}, _panel('board.playlist', state: {'playing': true}));
      expect(r.stateUpdate!['playing'], false);
    });

    test('remove', () async {
      final p = _panel('board.playlist', state: {
        'playlist': [{'path': '/a.mp3', 'title': 'a'}]
      });
      final r = await h.handleAction('remove', {'index': 0}, p);
      expect((r.stateUpdate!['playlist'] as List), isEmpty);
    });

    test('list returns playlist', () async {
      final r = await h.handleAction('list', {}, _panel('board.playlist'));
      expect(r.ok, isTrue);
      expect(r.data!['playlist'], isA<List>());
    });
  });

  group('ChecklistCliHandler', () {
    final h = const ChecklistCliHandler();

    test('add item', () async {
      final r = await h.handleAction('add', {'text': 'Buy milk'}, _panel('board.checklist'));
      expect(r.ok, isTrue);
      final items = r.stateUpdate!['items'] as List;
      expect(items.length, 1);
      expect(items[0]['text'], 'Buy milk');
      expect(items[0]['done'], false);
    });

    test('check item', () async {
      final p = _panel('board.checklist', state: {
        'items': [{'text': 'A', 'checked': false}]
      });
      final r = await h.handleAction('check', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List)[0]['done'], true);
    });

    test('uncheck item', () async {
      final p = _panel('board.checklist', state: {
        'items': [{'text': 'A', 'checked': true}]
      });
      final r = await h.handleAction('uncheck', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List)[0]['done'], false);
    });

    test('remove item', () async {
      final p = _panel('board.checklist', state: {
        'items': [{'text': 'A', 'checked': false}]
      });
      final r = await h.handleAction('remove', {'index': 0}, p);
      expect((r.stateUpdate!['items'] as List), isEmpty);
    });

    test('rename item', () async {
      final p = _panel('board.checklist', state: {
        'items': [{'text': 'Old', 'checked': false}]
      });
      final r = await h.handleAction('rename', {'index': 0, 'text': 'New'}, p);
      expect((r.stateUpdate!['items'] as List)[0]['text'], 'New');
    });
  });

  group('CodeSnippetCliHandler', () {
    final h = const CodeSnippetCliHandler();

    test('set code', () async {
      final r = await h.handleAction(
          'set', {'code': 'print("hi")', 'language': 'python'}, _panel('board.code.snippet'));
      expect(r.stateUpdate!['code'], 'print("hi")');
      expect(r.stateUpdate!['language'], 'python');
    });

    test('get code', () async {
      final p = _panel('board.code.snippet', state: {'code': 'x=1', 'language': 'python'});
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
      final r = await h.handleAction('open', {'path': '/home'}, _panel('board.files'));
      expect(r.stateUpdate!['selectedPath'], '/home');
    });

    test('get returns path', () async {
      final p = _panel('board.files', state: {'selectedPath': '/docs'});
      final r = await h.handleAction('get', {}, p);
      expect(r.data!['selectedPath'], '/docs');
    });
  });

  group('FilePreviewCliHandler', () {
    final h = const FilePreviewCliHandler();

    test('open sets file', () async {
      final r = await h.handleAction('open', {'path': '/img.png'}, _panel('board.file.preview'));
      expect(r.stateUpdate!['filePath'], '/img.png');
    });

    test('get returns file', () async {
      final p = _panel('board.file.preview', state: {'filePath': '/img.png'});
      final r = await h.handleAction('get', {}, p);
      expect(r.data!['filePath'], '/img.png');
    });
  });

  group('TerminalCliHandler', () {
    final h = const TerminalCliHandler();

    test('set-dir sets working directory', () async {
      final r = await h.handleAction('set-dir', {'dir': '/home'}, _panel('board.terminal'));
      expect(r.stateUpdate!['config']['workingDir'], '/home');
    });

    test('config returns config', () async {
      final p = _panel('board.terminal', state: {'config': {'workingDir': '/tmp'}});
      final r = await h.handleAction('config', {}, p);
      expect(r.data!['config']['workingDir'], '/tmp');
    });
  });
}
