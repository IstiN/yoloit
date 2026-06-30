// covers: panel:types, panel:color, panel:help, template:list, template:sync, board:delete, board:undo, group:rename, group:color, group:collapse, group:expand, group:move, group:add, group:remove, group:delete, link:delete, link:color, link:style, table:remove-row, table:add-column, table:remove-column, table:clear, note:get, code:set, calendar:create, calendar:add-event, calendar:events, calendar:delete-event, chart:create, chart:set-data, chart:set-type, files:list, shape:create, sticky:create, checklist:new, checklist:add, checklist:items, checklist:check, kanban:add-column, kanban:add-card, kanban:cards, filetree:create, filetree:list, ui:create, ui:render, ui:get

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI against local yoloitd - extended panel commands', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'local-panel-types-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_panel_types');
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

    test('panel types and metadata helpers', () async {
      await cli.json(['board:create', 'Types Board']);

      final types = await cli.json(['panel:types', 'Types Board']);
      expect(types['types'], isList);
      final typeIds =
          (types['types'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((t) => t['type'])
              .toList();
      expect(typeIds, contains('board.note.markdown'));

      final note = await cli.json([
        'panel:create',
        'Types Board',
        'board.note.markdown',
        'Meta Note',
      ]);
      expect(note['ok'], isTrue);

      final help = await cli.json(['panel:help', 'Types Board', 'Meta Note']);
      expect(help['panelType'], 'board.note.markdown');
      final actions = help['supportedActions'] as List<dynamic>;
      expect(actions, contains('set'));

      final colored = await cli.json([
        'panel:color',
        'Types Board',
        'Meta Note',
        '#ffcc00',
      ]);
      expect(colored['ok'], isTrue);

      final details = await cli.json(['panel', 'Types Board', 'Meta Note']);
      expect(details['color'], 0xffcc00);
    });

    test('templates', () async {
      final list = await cli.json(['template:list']);
      expect(list['ok'], isTrue);
      expect(list['templates'], isList);

      final sync = await cli.json(['template:sync']);
      expect(sync['ok'], isTrue);
    });

    test('board delete and undo', () async {
      await cli.json(['board:create', 'Delete Me']);
      final boards = await cli.json(['boards']);
      final names =
          (boards['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((b) => b['name'])
              .toList();
      expect(names, contains('Delete Me'));

      final deleted = await cli.json(['board:delete', 'Delete Me']);
      expect(deleted['ok'], isTrue);

      final boardsAfter = await cli.json(['boards']);
      final namesAfter =
          (boardsAfter['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((b) => b['name'])
              .toList();
      expect(namesAfter, isNot(contains('Delete Me')));

      final undoBoard = await cli.json(['board:create', 'Undo Board']);
      expect(undoBoard['ok'], isTrue);
      final note = await cli.json([
        'panel:create',
        'Undo Board',
        'board.note.markdown',
        'Undo Note',
      ]);
      expect(note['ok'], isTrue);

      final undone = await cli.json(['board:undo', 'Undo Board']);
      expect(undone['ok'], isTrue);

      final panels = await cli.json(['panels', 'Undo Board']);
      final titles =
          (panels['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((p) => p['title'])
              .toList();
      expect(titles, isNot(contains('Undo Note')));
    });

    test('group and link management', () async {
      await cli.json(['board:create', 'Group Board']);
      final note = await cli.json([
        'panel:create',
        'Group Board',
        'board.note.markdown',
        'Grouped Note',
      ]);
      final noteId = (note['panel'] as Map<String, dynamic>)['id'] as String;

      final group = await cli.json([
        'group:create',
        'Group Board',
        'Research',
        'Grouped Note',
      ]);
      expect(group['ok'], isTrue);
      final groupId = (group['group'] as Map<String, dynamic>)['id'] as String;

      final renamed = await cli.json([
        'group:rename',
        'Group Board',
        groupId,
        'Renamed Group',
      ]);
      expect(renamed['ok'], isTrue);

      final colored = await cli.json([
        'group:color',
        'Group Board',
        groupId,
        '#3B82F6',
      ]);
      expect(colored['ok'], isTrue);

      final collapsed = await cli.json([
        'group:collapse',
        'Group Board',
        groupId,
      ]);
      expect(collapsed['ok'], isTrue);

      final expanded = await cli.json([
        'group:expand',
        'Group Board',
        groupId,
      ]);
      expect(expanded['ok'], isTrue);

      final moved = await cli.json([
        'group:move',
        'Group Board',
        groupId,
        '10',
        '20',
      ]);
      expect(moved['ok'], isTrue);

      final secondNote = await cli.json([
        'panel:create',
        'Group Board',
        'board.note.markdown',
        'Second Note',
      ]);
      final secondId = (secondNote['panel'] as Map<String, dynamic>)['id'] as String;

      final added = await cli.json([
        'group:add',
        'Group Board',
        groupId,
        'Second Note',
      ]);
      expect(added['ok'], isTrue);

      final removed = await cli.json([
        'group:remove',
        'Group Board',
        groupId,
        'Second Note',
      ]);
      expect(removed['ok'], isTrue);

      final link = await cli.json([
        'link:create',
        'Group Board',
        'Grouped Note',
        'Second Note',
      ]);
      expect(link['ok'], isTrue);
      final linkId = (link['link'] as Map<String, dynamic>)['id'] as String;

      final styled = await cli.json([
        'link:style',
        'Group Board',
        linkId,
        'arrow',
        'straight',
      ]);
      expect(styled['ok'], isTrue);

      final linkColor = await cli.json([
        'link:color',
        'Group Board',
        linkId,
        '#7c3aed',
      ]);
      expect(linkColor['ok'], isTrue);

      final deleted = await cli.json(['link:delete', 'Group Board', linkId]);
      expect(deleted['ok'], isTrue);

      final links = await cli.json(['links', 'Group Board']);
      expect((links['links'] as List<dynamic>), isEmpty);

      final groupDeleted = await cli.json([
        'group:delete',
        'Group Board',
        groupId,
      ]);
      expect(groupDeleted['ok'], isTrue);

      final panels = await cli.json(['panels', 'Group Board']);
      final panelIds =
          (panels['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((p) => p['id'] as String)
              .toSet();
      expect(panelIds, contains(noteId));
      expect(panelIds, contains(secondId));
    });

    test('table editing', () async {
      await cli.json(['board:create', 'Table Edit Board']);
      await cli.json(['table:create', 'Table Edit Board', 'Sales']);
      await cli.json([
        'table:set',
        'Table Edit Board',
        'Sales',
        '[{"id":"month","title":"Month","type":"text"},{"id":"sales","title":"Sales","type":"number"}]',
        '[{"id":"r-1","month":"Jan","sales":100}]',
      ]);

      final addColumn = await cli.json([
        'table:add-column',
        'Table Edit Board',
        'Sales',
        'region',
        'Region',
        'text',
      ]);
      expect(addColumn['ok'], isTrue);

      final removeColumn = await cli.json([
        'table:remove-column',
        'Table Edit Board',
        'Sales',
        'region',
      ]);
      expect(removeColumn['ok'], isTrue);

      final addRow = await cli.json([
        'table:add-row',
        'Table Edit Board',
        'Sales',
        '{"month":"Feb","sales":200}',
      ]);
      expect(addRow['ok'], isTrue);

      final removeRow = await cli.json([
        'table:remove-row',
        'Table Edit Board',
        'Sales',
        'r-1',
      ]);
      expect(removeRow['ok'], isTrue);

      final clear = await cli.json(['table:clear', 'Table Edit Board', 'Sales']);
      expect(clear['ok'], isTrue);

      final panel = await cli.json(['panel', 'Table Edit Board', 'Sales']);
      final rows = (panel['content'] as Map<String, dynamic>)['rows'] as List<dynamic>;
      expect(rows, isEmpty);
    });

    test('table:set unwraps nested cells map from tool schema', () async {
      await cli.json(['board:create', 'Nested Table Board']);
      await cli.json(['table:create', 'Nested Table Board', 'Expenses']);

      final setResult = await cli.json([
        'table:set',
        'Nested Table Board',
        'Expenses',
        '[{"id":"category","title":"Категория","type":"text"},{"id":"amount","title":"Сумма","type":"number"}]',
        '[{"id":"r1","cells":{"category":"Продукты","amount":3500}},{"id":"r2","cells":{"category":"Транспорт","amount":1200}}]',
      ]);
      expect(setResult['ok'], isTrue);

      final panel = await cli.json(['panel', 'Nested Table Board', 'Expenses']);
      final rows = (panel['content'] as Map<String, dynamic>)['rows'] as List<dynamic>;
      expect(rows.length, 2);
      final first = rows.first as Map<String, dynamic>;
      expect(first['category'], 'Продукты');
      expect(first['amount'], 3500);
      expect(first.containsKey('cells'), isFalse);
      final second = rows.last as Map<String, dynamic>;
      expect(second['category'], 'Транспорт');
      expect(second['amount'], 1200);
    });

    test('note and code panels', () async {
      await cli.json(['board:create', 'Note Board']);
      final note = await cli.json([
        'panel:create',
        'Note Board',
        'board.note.markdown',
        'Readme',
      ]);
      expect(note['ok'], isTrue);

      await cli.json([
        'do',
        'Note Board',
        'Readme',
        'set',
        '{"text":"Hello note"}',
      ]);

      final got = await cli.json(['note:get', 'Note Board', 'Readme']);
      final content = got['content'] as Map<String, dynamic>;
      expect(content['markdown'], 'Hello note');

      final code = await cli.json([
        'panel:create',
        'Note Board',
        'board.code.snippet',
        'Snippet',
      ]);
      expect(code['ok'], isTrue);

      final setCode = await cli.json([
        'code:set',
        'Note Board',
        'Snippet',
        'print(1)',
      ]);
      expect(setCode['ok'], isTrue);

      final codePanel = await cli.json(['panel', 'Note Board', 'Snippet']);
      final codeContent = codePanel['content'] as Map<String, dynamic>;
      expect(codeContent['code'], 'print(1)');
    });

    test('calendar panel', () async {
      await cli.json(['board:create', 'Calendar Board']);
      final calendarId = await plain(['calendar:create', 'Calendar Board', 'Sprint']);
      expect(calendarId, isNotEmpty);

      final added = await cli.json([
        'calendar:add-event',
        'Calendar Board',
        'Sprint',
        'Standup',
        '2026-06-19T10:00:00',
      ]);
      expect(added['ok'], isTrue);
      final eventData = (added['data'] as Map<String, dynamic>)['event'] as Map<String, dynamic>;
      final eventId = eventData['id'] as String;

      final events = await cli.json([
        'calendar:events',
        'Calendar Board',
        'Sprint',
      ]);
      final eventList = (events['data'] as Map<String, dynamic>)['events'] as List<dynamic>;
      expect(eventList, hasLength(1));

      final deleted = await cli.json([
        'calendar:delete-event',
        'Calendar Board',
        'Sprint',
        eventId,
      ]);
      expect(deleted['ok'], isTrue);

      final eventsAfter = await cli.json([
        'calendar:events',
        'Calendar Board',
        'Sprint',
      ]);
      final afterList = (eventsAfter['data'] as Map<String, dynamic>)['events'] as List<dynamic>;
      expect(afterList, isEmpty);
    });

    test('chart panel', () async {
      await cli.json(['board:create', 'Chart Board']);
      final chart = await cli.json(['chart:create', 'Chart Board', 'Revenue']);
      expect(chart['ok'], isTrue);

      final setData = await cli.json([
        'chart:set-data',
        'Chart Board',
        'Revenue',
        '[{"month":"Jan","sales":100},{"month":"Feb","sales":200}]',
      ]);
      expect(setData['ok'], isTrue);

      final setType = await cli.json([
        'chart:set-type',
        'Chart Board',
        'Revenue',
        'bar',
      ]);
      expect(setType['ok'], isTrue);

      final panel = await cli.json(['panel', 'Chart Board', 'Revenue']);
      final content = panel['content'] as Map<String, dynamic>;
      expect(content['type'], 'bar');
      expect((content['data'] as List<dynamic>), hasLength(2));
    });

    test('ui view panel', () async {
      await cli.json(['board:create', 'UI Board']);
      final created = await cli.json(['ui:create', 'UI Board', 'Dashboard']);
      expect(created['ok'], isTrue);
      final panel = created['panel'] as Map<String, dynamic>;
      expect(panel['type'], 'board.ui');
      expect(panel['title'], 'Dashboard');

      const tree =
          '{"type":"column","children":[{"type":"text","data":"Hello UI"}]}';
      final rendered = await cli.json([
        'ui:render',
        'UI Board',
        'Dashboard',
        tree,
      ]);
      expect(rendered['ok'], isTrue);

      final got = await cli.json(['ui:get', 'UI Board', 'Dashboard']);
      expect(got['ok'], isTrue);
      final data = got['data'] as Map<String, dynamic>;
      final gotTree = data['tree'] as Map<String, dynamic>;
      expect(gotTree['type'], 'column');
      final children = gotTree['children'] as List<dynamic>;
      expect((children.first as Map<String, dynamic>)['data'], 'Hello UI');
      final textLines = data['text'] as List<dynamic>;
      expect(textLines, contains('Hello UI'));
    });

    test('files and filetree', () async {
      final dir = Directory('${cli.homeDir.path}/sample_dir');
      await dir.create();
      await File('${dir.path}/hello.txt').writeAsString('hi');

      final list = await cli.json(['files:list', dir.path]);
      expect(list['ok'], isTrue);
      final names =
          (list['entries'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((e) => e['name'])
              .toList();
      expect(names, contains('hello.txt'));

      await cli.json(['board:create', 'Filetree Board']);
      final tree = await cli.json([
        'filetree:create',
        'Filetree Board',
        dir.path,
        '--title',
        'Project Tree',
      ]);
      expect(tree['ok'], isTrue);

      final listed = await cli.json(['filetree:list', 'Filetree Board', 'Project Tree']);
      expect(listed['ok'], isTrue);
    });

    test('shape, sticky, checklist and kanban panels', () async {
      await cli.json(['board:create', 'Widgets Board']);

      final shapeOut = await plain([
        'shape:create',
        'Widgets Board',
        'diamond',
        'Decision',
      ]);
      expect(shapeOut, contains('Shape panel created'));

      final stickyOut = await plain([
        'sticky:create',
        'Widgets Board',
        'Idea',
        'Ship it',
      ]);
      expect(stickyOut, contains('Sticky panel created'));

      final checklistOut = await plain([
        'checklist:new',
        'Widgets Board',
        'Todo',
      ]);
      expect(checklistOut, contains('Checklist panel created'));

      final addItem = await cli.json([
        'checklist:add',
        'Widgets Board',
        'Todo',
        'Buy milk',
      ]);
      expect(addItem['ok'], isTrue);

      final checkItem = await cli.json([
        'checklist:check',
        'Widgets Board',
        'Todo',
        'Buy milk',
      ]);
      expect(checkItem['ok'], isTrue);

      final items = await cli.json(['checklist:items', 'Widgets Board', 'Todo']);
      final itemList = (items['data'] as Map<String, dynamic>)['items'] as List<dynamic>;
      expect(itemList, hasLength(1));
      final firstItem = itemList.first as Map<String, dynamic>;
      expect(firstItem['text'], 'Buy milk');
      expect(firstItem['done'], isTrue);

      final kanban = await cli.json([
        'panel:create',
        'Widgets Board',
        'board.kanban',
        'Tasks',
      ]);
      expect(kanban['ok'], isTrue);

      final addCol = await cli.json([
        'kanban:add-column',
        'Widgets Board',
        'Tasks',
        'Done',
      ]);
      expect(addCol['ok'], isTrue);

      final addCard = await cli.json([
        'kanban:add-card',
        'Widgets Board',
        'Tasks',
        'Done',
        'Celebrate',
      ]);
      expect(addCard['ok'], isTrue);

      final cards = await cli.json(['kanban:cards', 'Widgets Board', 'Tasks']);
      final cardsData = cards['cards'] ?? cards['data'];
      expect(cardsData, isNotNull);
    });
  });
}
