// covers: remote:status, boards, board:create, board:rename, panel:create, panel:rename, panel:move, panel:resize, do, panel, group:create, groups, link:create, links, board:archive, board:unarchive, table:create, table:set, table:add-row, table:update-row, panel:delete, panels

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';

import '../helpers/yoloit_cli_harness.dart';

void main() {
  group('real yoloit CLI against local yoloitd server', () {
    late Directory tempDir;
    late YoloitdServer server;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'local-secret';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_local_test');
      final store = YoloitdStore(
        rootDir: tempDir,
        actorId: 'test',
      );
      server = YoloitdServer(
        store: store,
        host: '127.0.0.1',
        port: 0,
        token: token,
      );
      await server.start();
      baseUrl = 'http://127.0.0.1:${server.boundPort}';

      cli = await YoloitCliHarness.create(
        baseUrl: baseUrl,
        token: token,
      );
    });

    tearDown(() async {
      await cli.dispose();
      await server.stop();
      tempDir.deleteSync(recursive: true);
    });

    test('board and panel lifecycle', () async {
      final status = await cli.json(['remote:status']);
      expect(status['ok'], isTrue);
      expect(status['mode'], 'remote');

      final boardsBefore = await cli.json(['boards']);
      expect(boardsBefore['boards'], isList);

      final created = await cli.json(['board:create', 'CLI Local Board']);
      expect(created['ok'], isTrue);

      final boards = await cli.json(['boards']);
      final names =
          (boards['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((board) => board['name'])
              .toList();
      expect(names, contains('CLI Local Board'));

      final renamed = await cli.json(
        ['board:rename', 'CLI Local Board', 'Renamed CLI Board'],
      );
      expect(renamed['ok'], isTrue);

      final notePanel = await cli.json(
        ['panel:create', 'Renamed CLI Board', 'board.note.markdown', 'Notes'],
      );
      expect(notePanel['ok'], isTrue);

      final renamedPanel = await cli.json(
        ['panel:rename', 'Renamed CLI Board', 'Notes', 'Notes v2'],
      );
      expect(renamedPanel['ok'], isTrue);

      final moved = await cli.json(
        ['panel:move', 'Renamed CLI Board', 'Notes v2', '200', '150'],
      );
      expect(moved['ok'], isTrue);

      final resized = await cli.json(
        ['panel:resize', 'Renamed CLI Board', 'Notes v2', '500', '300'],
      );
      expect(resized['ok'], isTrue);

      final noteSet = await cli.json([
        'do',
        'Renamed CLI Board',
        'Notes v2',
        'set',
        '{"text":"Hello from CLI"}',
      ]);
      expect(noteSet['ok'], isTrue);

      final panelDetails = await cli.json(
        ['panel', 'Renamed CLI Board', 'Notes v2'],
      );
      expect(panelDetails['type'], 'board.note.markdown');
      final content = panelDetails['content'] as Map<String, dynamic>;
      expect(content['markdown'], 'Hello from CLI');
      final bounds = panelDetails['bounds'] as Map<String, dynamic>;
      expect(bounds['x'], 200);
      expect(bounds['y'], 150);
      expect(bounds['width'], 500);
      expect(bounds['height'], 300);
      final notePanelId = panelDetails['id'] as String;

      final groupCreated = await cli.json(
        ['group:create', 'Renamed CLI Board', 'Research', 'Notes v2'],
      );
      expect(groupCreated['ok'], isTrue);
      final groupId = (groupCreated['group'] as Map<String, dynamic>)['id'] as String;

      final groups = await cli.json(['groups', 'Renamed CLI Board']);
      final matchedGroup =
          (groups['groups'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .firstWhere((group) => group['id'] == groupId);
      expect(matchedGroup['panelIds'], contains(notePanelId));

      final linkCreated = await cli.json(
        ['link:create', 'Renamed CLI Board', 'Notes v2', 'Notes v2'],
      );
      expect(linkCreated['ok'], isTrue);

      final links = await cli.json(['links', 'Renamed CLI Board']);
      final storedLinks =
          (links['links'] as List<dynamic>).whereType<Map<String, dynamic>>();
      expect(storedLinks, hasLength(1));
      expect(storedLinks.first['fromPanelId'], notePanelId);
      expect(storedLinks.first['toPanelId'], notePanelId);

      final archived = await cli.json(
        ['board:archive', 'Renamed CLI Board'],
      );
      expect(archived['ok'], isTrue);

      final boardsWithoutArchived = await cli.json(['boards']);
      final namesAfterArchive =
          (boardsWithoutArchived['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((board) => board['name'])
              .toList();
      expect(namesAfterArchive, isNot(contains('Renamed CLI Board')));

      final boardsWithArchived = await cli.json(['boards', '--archived']);
      final namesWithArchived =
          (boardsWithArchived['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((board) => board['name'])
              .toList();
      expect(namesWithArchived, contains('Renamed CLI Board'));

      final unarchived = await cli.json(
        ['board:unarchive', 'Renamed CLI Board'],
      );
      expect(unarchived['ok'], isTrue);

      final tablePanel = await cli.json(
        ['table:create', 'Renamed CLI Board', 'Sales'],
      );
      expect(tablePanel['ok'], isTrue);

      final tableSet = await cli.json([
        'table:set',
        'Renamed CLI Board',
        'Sales',
        '[{"id":"month","title":"Month","type":"text"},{"id":"sales","title":"Sales","type":"number"}]',
        '[{"id":"r-1","month":"Jan","sales":100}]',
      ]);
      expect(tableSet['ok'], isTrue);

      final tableInitial = await cli.json(
        ['panel', 'Renamed CLI Board', 'Sales'],
      );
      final initialState = tableInitial['content'] as Map<String, dynamic>;
      expect((initialState['columns'] as List<dynamic>).length, 2);
      expect((initialState['rows'] as List<dynamic>).length, 1);

      final addRow = await cli.json([
        'table:add-row',
        'Renamed CLI Board',
        'Sales',
        '{"month":"Apr","sales":210}',
      ]);
      expect(addRow['ok'], isTrue);

      final tableContent = await cli.json(
        ['panel', 'Renamed CLI Board', 'Sales'],
      );
      final tableState = tableContent['content'] as Map<String, dynamic>;
      final rows = tableState['rows'] as List<dynamic>;
      expect(rows, hasLength(2));
      expect(
        rows.whereType<Map<String, dynamic>>().any(
          (row) => row['month'] == 'Apr' && row['sales'] == 210,
        ),
        isTrue,
      );

      final rowId =
          (rows.firstWhere(
            (row) => (row as Map<String, dynamic>)['month'] == 'Jan',
          ) as Map<String, dynamic>)['id'] as String;

      final updateRow = await cli.json([
        'table:update-row',
        'Renamed CLI Board',
        'Sales',
        rowId,
        '{"sales":999}',
      ]);
      expect(updateRow['ok'], isTrue);

      final tableAfterUpdate = await cli.json(
        ['panel', 'Renamed CLI Board', 'Sales'],
      );
      final updatedRows =
          (tableAfterUpdate['content'] as Map<String, dynamic>)['rows']
              as List<dynamic>;
      final updatedRow = updatedRows
          .whereType<Map<String, dynamic>>()
          .firstWhere((row) => row['month'] == 'Jan');
      expect(updatedRow['sales'], 999);

      final deleted = await cli.json(
        ['panel:delete', 'Renamed CLI Board', 'Notes v2'],
      );
      expect(deleted['ok'], isTrue);

      final panelsAfterDelete = await cli.json(
        ['panels', 'Renamed CLI Board'],
      );
      final panelTitles =
          (panelsAfterDelete['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((panel) => panel['title'])
              .toList();
      expect(panelTitles, isNot(contains('Notes v2')));
    }, timeout: const Timeout(Duration(minutes: 5)));
  });
}
