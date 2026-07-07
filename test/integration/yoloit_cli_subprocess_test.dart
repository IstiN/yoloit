// covers: remote:status, boards, board:create, board:rename, panel:create, panel:rename, panel:move, panel:resize, do, panel, group:create, groups, link:create, links, board:archive, board:unarchive, table:create, table:set, table:add-row, table:update-row, panel:delete, panels

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../helpers/yoloit_cli_harness.dart';

Future<int> _findFreePort() async {
  final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final port = socket.port;
  await socket.close();
  return port;
}

void main() {
  group('real yoloit CLI against yoloitd subprocess', () {
    late Directory tempDir;
    String? binaryPath;
    String? skipReason;
    late Process serverProcess;
    late YoloitCliHarness cli;
    late String baseUrl;
    const token = 'subprocess-secret';

    setUpAll(() async {
      tempDir = Directory.systemTemp.createTempSync('yoloit_cli_subprocess_test');
      final candidatePath = '${tempDir.path}/yoloitd';
      final compile = await Process.run(
        'dart',
        ['compile', 'exe', 'bin/yoloitd.dart', '-o', candidatePath],
        workingDirectory: Directory.current.path,
      );
      if (compile.exitCode != 0) {
        final stderr = compile.stderr.toString();
        if (stderr.contains('does not support build hooks') ||
            stderr.contains('build hooks')) {
          skipReason = 'dart compile exe does not support build hooks in this SDK.';
          // Leave [binaryPath] null so the per-test guards below skip the suite.
          return;
        }
        fail(
          'Failed to compile yoloitd\nstdout: ${compile.stdout}\nstderr: ${compile.stderr}',
        );
      }
      binaryPath = candidatePath;
    });

    tearDownAll(() async {
      if (await Directory(tempDir.path).exists()) {
        await Directory(tempDir.path).delete(recursive: true);
      }
    });

    setUp(() async {
      if (binaryPath == null) return;
      final port = await _findFreePort();
      final dataDir = Directory('${tempDir.path}/data_$port');
      await dataDir.create(recursive: true);
      baseUrl = 'http://127.0.0.1:$port';

      serverProcess = await Process.start(
        binaryPath!,
        [
          '--host',
          '127.0.0.1',
          '--port',
          '$port',
          '--data-dir',
          dataDir.path,
          '--token',
          token,
        ],
      );

      // Wait for the server to accept connections.
      final deadline = DateTime.now().add(const Duration(seconds: 30));
      while (DateTime.now().isBefore(deadline)) {
        try {
          final request = await HttpClient()
              .getUrl(Uri.parse('$baseUrl/api/health'));
          request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final response = await request.close();
          if (response.statusCode == 200) {
            break;
          }
        } on SocketException {
          // Server not ready yet.
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      cli = await YoloitCliHarness.create(
        baseUrl: baseUrl,
        token: token,
      );
    });

    tearDown(() async {
      if (binaryPath == null) return;
      await cli.dispose();
      serverProcess.kill();
      await serverProcess.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          serverProcess.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    });

    test(
      'board and panel lifecycle',
      () async {
        if (binaryPath == null) {
          markTestSkipped(skipReason ?? 'dart compile exe is unavailable.');
          return;
        }
        final status = await cli.json(['remote:status']);
      expect(status['ok'], isTrue);
      expect(status['mode'], 'remote');

      final boardsBefore = await cli.json(['boards']);
      expect(boardsBefore['boards'], isList);

      final created = await cli.json(['board:create', 'CLI Subprocess Board']);
      expect(created['ok'], isTrue);

      final boards = await cli.json(['boards']);
      final names =
          (boards['boards'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .map((board) => board['name'])
              .toList();
      expect(names, contains('CLI Subprocess Board'));

      final renamed = await cli.json(
        ['board:rename', 'CLI Subprocess Board', 'Renamed CLI Board'],
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
