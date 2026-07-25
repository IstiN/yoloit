// covers: board, board:current, board:use, board:snapshot, board:diagram, boards:snapshot, note, note:add, note:create, note:append, note:wrap, note:nowrap, code:get, shape:get, shape:set, sticky:get, sticky:set, sticky:append, sticky:color, frame:create, checklist:uncheck, checklist:remove, checklist:rename, kanban:columns, kanban:rename-column, kanban:remove-column, kanban:move-card, kanban:remove-card, kanban:update-card, kanban:paste

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI against local yoloitd - remaining commands', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'local-remaining-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_remaining');
      server = YoloitdServer(
        store: YoloitdStore(rootDir: tempDir, actorId: 'test'),
        host: '127.0.0.1',
        port: 0,
        token: token,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';
      cli = await YoloitCliHarness.create(baseUrl: baseUrl, token: token);
    });

    tearDown(() async {
      await cli.dispose();
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    Future<String> plain(List<String> args) async {
      final result = await cli.run(args);
      expect(result.exitCode, 0, reason: result.stderr as String?);
      return (result.stdout as String).trim();
    }

    test('board metadata and snapshot helpers', () async {
      await cli.json(['board:create', 'Meta Board']);

      final useOut = await plain(['board:use', 'Meta Board']);
      expect(useOut, contains('Meta Board'));

      final current = await plain(['board:current']);
      expect(current, 'Meta Board');

      final board = await cli.json(['board', 'Meta Board']);
      expect(board['name'], 'Meta Board');

      await cli.json([
        'panel:create',
        'Meta Board',
        'board.note.markdown',
        'Snap Note',
      ]);

      final md = await plain(['board:snapshot', 'Meta Board']);
      expect(md, contains('# Meta Board'));
      expect(md, contains('Snap Note'));

      final mermaid = await plain(['board:diagram', 'Meta Board']);
      expect(mermaid, contains('| Panel | Type | Position | Size |'));

      final allBoards = await plain(['boards:snapshot']);
      expect(allBoards, contains('Meta Board'));
    });

    test('note lifecycle via smart commands', () async {
      await cli.json(['board:create', 'Note Smart Board']);
      final createOut = await plain([
        'note:create',
        'Note Smart Board',
        'Scratch',
        'Initial',
      ]);
      expect(createOut, contains('Note panel created'));

      final note = await cli.json([
        'note',
        'Note Smart Board',
        'Scratch',
        'Hello smart note',
      ]);
      expect(note['ok'], isTrue);

      final added = await cli.json([
        'note:add',
        'Note Smart Board',
        'Scratch',
        'Line two',
      ]);
      expect(added['ok'], isTrue);

      final appended = await cli.json([
        'note:append',
        'Note Smart Board',
        'Scratch',
        'Line three',
      ]);
      expect(appended['ok'], isTrue);

      final wrapped = await cli.json([
        'note:wrap',
        'Note Smart Board',
        'Scratch',
      ]);
      expect(wrapped['ok'], isTrue);

      final nowrap = await cli.json([
        'note:nowrap',
        'Note Smart Board',
        'Scratch',
      ]);
      expect(nowrap['ok'], isTrue);

      final panel = await cli.json(['panel', 'Note Smart Board', 'Scratch']);
      final content = panel['content'] as Map<String, dynamic>;
      expect(content['markdown'], contains('Hello smart note'));
    });

    test('code snippet panel', () async {
      await cli.json(['board:create', 'Code Board']);
      final code = await cli.json([
        'panel:create',
        'Code Board',
        'board.code.snippet',
        'Snippet',
      ]);
      expect(code['ok'], isTrue);

      await cli.json(['code:set', 'Code Board', 'Snippet', 'print(42)']);

      final got = await cli.json(['code:get', 'Code Board', 'Snippet']);
      final content = got['content'] as Map<String, dynamic>;
      expect(content['code'], 'print(42)');
    });

    test('shape and sticky panels', () async {
      await cli.json(['board:create', 'Shape Board']);
      final shapeOut = await plain([
        'shape:create',
        'Shape Board',
        'diamond',
        'Decision',
      ]);
      expect(shapeOut, contains('Shape panel created'));

      final shapeGet = await cli.json(['shape:get', 'Shape Board', 'Decision']);
      final shapeContent = shapeGet['content'] as Map<String, dynamic>;
      expect(shapeContent['shape'], 'diamond');

      final shapeSet = await cli.json([
        'shape:set',
        'Shape Board',
        'Decision',
        'text',
        'Go',
        'fill',
        '#ff0000',
      ]);
      expect(shapeSet['ok'], isTrue);

      final stickyOut = await plain([
        'sticky:create',
        'Shape Board',
        'Idea',
        'First',
      ]);
      expect(stickyOut, contains('Sticky panel created'));

      final stickyGet = await cli.json(['sticky:get', 'Shape Board', 'Idea']);
      final stickyContent = stickyGet['content'] as Map<String, dynamic>;
      expect(stickyContent['text'], 'First');

      final stickySet = await cli.json([
        'sticky:set',
        'Shape Board',
        'Idea',
        'Updated',
      ]);
      expect(stickySet['ok'], isTrue);

      final stickyAppend = await cli.json([
        'sticky:append',
        'Shape Board',
        'Idea',
        '!',
      ]);
      expect(stickyAppend['ok'], isTrue);

      final stickyColor = await cli.json([
        'sticky:color',
        'Shape Board',
        'Idea',
        '#A7F3D0',
      ]);
      expect(stickyColor['ok'], isTrue);

      final frameOut = await plain(['frame:create', 'Shape Board', 'Scope']);
      expect(frameOut, contains('Frame panel created'));
    });

    test('checklist editing', () async {
      await cli.json(['board:create', 'Checklist Edit Board']);
      await plain(['checklist:new', 'Checklist Edit Board', 'Tasks']);

      await cli.json([
        'checklist:add',
        'Checklist Edit Board',
        'Tasks',
        'One',
      ]);
      await cli.json([
        'checklist:add',
        'Checklist Edit Board',
        'Tasks',
        'Two',
      ]);

      final check = await cli.json([
        'checklist:check',
        'Checklist Edit Board',
        'Tasks',
        'One',
      ]);
      expect(check['ok'], isTrue);

      final uncheck = await cli.json([
        'checklist:uncheck',
        'Checklist Edit Board',
        'Tasks',
        'One',
      ]);
      expect(uncheck['ok'], isTrue);

      final rename = await cli.json([
        'checklist:rename',
        'Checklist Edit Board',
        'Tasks',
        'Two',
        'Second',
      ]);
      expect(rename['ok'], isTrue);

      final remove = await cli.json([
        'checklist:remove',
        'Checklist Edit Board',
        'Tasks',
        'Second',
      ]);
      expect(remove['ok'], isTrue);

      final items = await cli.json([
        'checklist:items',
        'Checklist Edit Board',
        'Tasks',
      ]);
      final itemList = (items['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
      expect(itemList, hasLength(1));
      expect((itemList.first as Map<String, dynamic>)['text'], 'One');
    });

    test('kanban editing', () async {
      await cli.json(['board:create', 'Kanban Edit Board']);
      final kanban = await cli.json([
        'panel:create',
        'Kanban Edit Board',
        'board.kanban',
        'Tasks',
      ]);
      expect(kanban['ok'], isTrue);

      final columns = await cli.json([
        'kanban:columns',
        'Kanban Edit Board',
        'Tasks',
      ]);
      final columnList = (columns['data'] as Map<String, dynamic>)['columns'] as List<dynamic>;
      expect(columnList, isNotEmpty);

      // Flag-style board/panel args should work identically to positional args.
      final columnsByFlag = await cli.json([
        'kanban:columns',
        '--board',
        'Kanban Edit Board',
        '--panel',
        'Tasks',
      ]);
      expect(columnsByFlag['ok'], isTrue);
      final columnListByFlag = (columnsByFlag['data'] as Map<String, dynamic>)['columns'] as List<dynamic>;
      expect(columnListByFlag, equals(columnList));

      await cli.json([
        'kanban:add-column',
        'Kanban Edit Board',
        'Tasks',
        'Done',
      ]);

      // Regression test: kanban:paste used to reference an undefined _port variable.
      final pasted = await cli.json([
        'kanban:paste',
        'Pasted card\nDescription line',
        'Todo',
        'Tasks',
        'Kanban Edit Board',
      ]);
      expect(pasted['ok'], isTrue);

      final renamed = await cli.json([
        'kanban:rename-column',
        'Kanban Edit Board',
        'Tasks',
        'Done',
        'Shipped',
      ]);
      expect(renamed['ok'], isTrue);

      final card = await cli.json([
        'kanban:add-card',
        'Kanban Edit Board',
        'Tasks',
        'Shipped',
        'Release',
      ]);
      expect(card['ok'], isTrue);
      final cardId = (card['data'] as Map<String, dynamic>)['cardId'] as String;

      final moved = await cli.json([
        'kanban:move-card',
        'Kanban Edit Board',
        'Tasks',
        cardId,
        'Todo',
      ]);
      expect(moved['ok'], isTrue);

      final updated = await cli.json([
        'kanban:update-card',
        'Kanban Edit Board',
        'Tasks',
        cardId,
        'Release v2',
      ]);
      expect(updated['ok'], isTrue);

      final cards = await cli.json([
        'kanban:cards',
        'Kanban Edit Board',
        'Tasks',
      ]);
      final cardsData = cards['data'] as Map<String, dynamic>;
      final cardList = cardsData['cards'] as List<dynamic>;
      expect(cardList, hasLength(2));

      final removedCol = await cli.json([
        'kanban:remove-column',
        'Kanban Edit Board',
        'Tasks',
        'Shipped',
      ]);
      expect(removedCol['ok'], isTrue);

      final removedCard = await cli.json([
        'kanban:remove-card',
        'Kanban Edit Board',
        'Tasks',
        cardId,
      ]);
      expect(removedCard['ok'], isTrue);
    });


  });
}
