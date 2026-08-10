import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/cli/cli_server.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/templates/data/template_sources_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

import 'cli_server_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    home = await Directory.systemTemp.createTemp('cli-server-boards-test-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    await _seedTemplateSources(home);
  });

  tearDown(() async {
    await CliServer.instance.stop();
    PlatformDirs.reset();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  group('create board', () {
    test('creates a board with a default name', () async {
      final cubit = await startServer();

      final res = await apiJson('POST', '/api/boards', body: const {});

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      final board = res.json['board'] as Map<String, dynamic>;
      expect(board['name'], 'New Board');
      expect(cubit.state.boards.length, 2);
      expect(cubit.state.activeBoardId, board['id']);
    });

    test('creates a board with the given name', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards',
        body: const {'name': 'Sprint 42'},
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      final created = cubit.state.boards.firstWhere((b) => b.id != 'board');
      expect(created.name, 'Sprint 42');
    });

    test('returns 404 for an unknown template', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards',
        body: const {'templateId': 'ghost'},
      );

      expect(res.status, 404);
      expect(res.json['error'], contains('Template not found: ghost'));
    });

    test('returns 400 when template parameters fail validation', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards',
        body: const {'templateId': 'cli-template'},
      );

      expect(res.status, 400, reason: res.body);
      expect(res.json['ok'], false);
      final errors = res.json['errors'] as Map<String, dynamic>;
      expect(errors['boardTitle'], 'Required');
    });

    test('creates a board from a template with interpolated params', () async {
      final cubit = await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards',
        body: const {
          'name': 'From Template',
          'template': 'cli-template',
          'params': {'boardTitle': 'Hello Board'},
        },
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      expect(res.json['templateId'], 'cli-template');
      expect(res.json['panelCount'], 1);
      final created = cubit.state.boards.firstWhere(
        (b) => b.name == 'From Template',
      );
      expect(created.panels.single.type, 'board.sticky');
      expect(created.panels.single.title, 'Hello Board');
    });
  });

  group('create link', () {
    test('requires from and to panel ids', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/boards/board/links',
        body: const {'from': 'p1'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Missing "from" or "to"'));
    });

    test('fails when the source panel is unknown', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'POST',
        '/api/boards/board/links',
        body: const {'from': 'ghost', 'to': 'p1'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Panel not found: ghost'));
    });

    test('fails when the target panel is unknown', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await apiJson(
        'POST',
        '/api/boards/board/links',
        body: const {'from': 'p1', 'to': 'ghost'},
      );

      expect(res.status, 400);
      expect(res.json['error'], contains('Panel not found: ghost'));
    });

    test('creates a link with explicit style and geometry', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'A'), stickyPanel('p2', 'B', x: 400)],
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/links',
        body: const {
          'from': 'p1',
          'to': 'p2',
          'style': 'line',
          'geometry': 'elbow',
        },
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      final link = cubit.state.boards.single.links.single;
      expect(link.fromPanelId, 'p1');
      expect(link.toPanelId, 'p2');
      expect(link.style, BoardLinkStyle.line);
      expect(link.geometry, BoardLinkGeometry.elbow);
    });

    test('resolves panel titles and falls back for unknown style', () async {
      final cubit = await startServer(
        panels: [stickyPanel('p1', 'Alpha'), stickyPanel('p2', 'Beta', x: 400)],
      );

      final res = await apiJson(
        'POST',
        '/api/boards/board/links',
        body: const {
          'from': 'alpha',
          'to': 'BETA',
          'style': 'nope',
          'geometry': 'nope',
        },
      );

      expect(res.status, 200, reason: res.body);
      final link = cubit.state.boards.single.links.single;
      expect(link.fromPanelId, 'p1');
      expect(link.toPanelId, 'p2');
      expect(link.style, BoardLinkStyle.arrow);
      expect(link.geometry, BoardLinkGeometry.bezier);
    });
  });

  group('sync templates', () {
    test('syncs all sources and returns the template list', () async {
      await startServer();

      final res = await apiJson('POST', '/api/templates', body: const {});

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      final templates = res.json['templates'] as List<dynamic>;
      // Built-in templates are always present; the seeded local source
      // contributes the cli-template entry.
      expect(res.json['templateCount'], templates.length);
      final ids = templates
          .map((t) => (t as Map<String, dynamic>)['id'])
          .toList();
      expect(ids, contains('cli-template'));
    });

    test('syncs when the requested source has templates', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/templates',
        body: const {'sourceId': 'local-cli'},
      );

      expect(res.status, 200, reason: res.body);
      expect(res.json['ok'], true);
      final templates = res.json['templates'] as List<dynamic>;
      expect(res.json['templateCount'], templates.length);
      final ids = templates
          .map((t) => (t as Map<String, dynamic>)['id'])
          .toList();
      expect(ids, contains('cli-template'));
    });

    test('returns 404 for an unknown source id', () async {
      await startServer();

      final res = await apiJson(
        'POST',
        '/api/templates',
        body: const {'sourceId': 'ghost'},
      );

      expect(res.status, 404);
      expect(res.json['error'], contains('Template source not found: ghost'));
    });
  });

  group('board screenshot', () {
    test('fails for the active board without a capture boundary', () async {
      await startServer(panels: [stickyPanel('p1', 'A')]);

      final res = await httpRequest('GET', '/api/boards/board/screenshot');

      expect(res.status, 400);
      expect(res.body, contains('Failed to capture board screenshot'));
    });

    test('fails offscreen for a board without visible panels', () async {
      await startServer();

      final res = await httpRequest(
        'GET',
        '/api/boards/board/screenshot?mode=offscreen',
      );

      expect(res.status, 400);
      expect(res.body, contains('Failed to capture board screenshot'));
    });

    test('captures a non-active board offscreen', () async {
      final cubit = await startServer(panels: [stickyPanel('p1', 'A')]);
      cubit.emit(
        BoardState(
          boards: [
            cubit.state.boards.single,
            const BoardDocument(id: 'other', name: 'Other'),
          ],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      final res = await httpRequest('GET', '/api/boards/other/screenshot');

      expect(res.status, 400);
      expect(res.body, contains('Failed to capture board screenshot'));
    });

    test(
      'offscreen mode returns a PNG for a board with panels',
      () async {
        await startServer(panels: [stickyPanel('p1', 'A')]);

        final res = await httpBinaryRequest(
          'GET',
          '/api/boards/board/screenshot?mode=offscreen',
        );

        expect(res.status, 200, reason: res.head);
        expect(res.head.toLowerCase(), contains('content-type: image/png'));
        expect(res.bodyBytes.length, greaterThan(100));
        expect(res.bodyBytes.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  });
}

/// Seeds a disabled default GitHub source (so tests never hit the network)
/// plus an enabled local source with a single parameterized template.
Future<void> _seedTemplateSources(Directory home) async {
  final templatesRoot = Directory(p.join(home.path, 'templates'));
  final templateDir = Directory(p.join(templatesRoot.path, 'cli-template'));
  await templateDir.create(recursive: true);
  await File(p.join(templateDir.path, 'template.yaml')).writeAsString('''
id: cli-template
name: CLI Template
description: Template used by CLI server tests
parameters:
  - name: boardTitle
    type: string
    label: Board Title
    required: true
operations:
  - op: panel.create
    type: board.sticky
    title: '{{boardTitle}}'
''');
  final sourcesFile = File(
    p.join(PlatformDirs.instance.configDir, 'template_sources.json'),
  );
  await sourcesFile.parent.create(recursive: true);
  await sourcesFile.writeAsString(
    encodeSourcesJson([
      buildDefaultSource().copyWith(enabled: false),
      TemplateSource(
        id: 'local-cli',
        type: TemplateSourceType.local,
        localPath: templatesRoot.path,
      ),
    ]),
  );
}

/// Binary-safe variant of the harness `httpRequest` for endpoints that
/// return non-UTF8 payloads (e.g. PNG screenshots).
Future<({int status, String head, List<int> bodyBytes})> httpBinaryRequest(
  String method,
  String path,
) async {
  final port = CliServer.instance.port!;
  final socket = await Socket.connect('127.0.0.1', port);
  socket.write(
    [
      '$method $path HTTP/1.1',
      'Host: 127.0.0.1:$port',
      'Content-Length: 0',
      'Connection: close',
      '',
      '',
    ].join('\r\n'),
  );
  await socket.flush();
  final bytes = await socket.fold<List<int>>(
    <int>[],
    (buffer, chunk) => buffer..addAll(chunk),
  );
  await socket.close();
  var split = -1;
  for (var i = 0; i + 3 < bytes.length; i++) {
    if (bytes[i] == 13 &&
        bytes[i + 1] == 10 &&
        bytes[i + 2] == 13 &&
        bytes[i + 3] == 10) {
      split = i;
      break;
    }
  }
  expect(split, greaterThanOrEqualTo(0));
  final head = ascii.decode(bytes.sublist(0, split));
  final statusMatch = RegExp(r'^HTTP/\d\.\d\s+(\d+)').firstMatch(head);
  return (
    status: int.parse(statusMatch!.group(1)!),
    head: head,
    bodyBytes: bytes.sublist(split + 4),
  );
}
