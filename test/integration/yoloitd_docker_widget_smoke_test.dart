import 'dart:io';

import 'package:test/test.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';

import '../helpers/remote_widget_smoke_data.dart';
import '../helpers/yoloitd_docker_harness.dart';

void main() {
  final runDocker = Platform.environment['YOLOIT_RUN_DOCKER_TESTS'] == '1';

  setUp(() {
    HttpOverrides.global = null;
  });

  test(
    'yoloitd docker container round-trips every remote widget type',
    () async {
      final harness = await YoloitdDockerHarness.start();
      addTearDown(harness.dispose);

      final created = await harness.json(
        'POST',
        '/api/boards',
        body: {'name': 'Docker Remote Widgets'},
      );
      final board = created['board'] as Map<String, dynamic>;
      final boardId = board['id'] as String;

      final typesResponse = await harness.json(
        'GET',
        '/api/boards/$boardId/panel-types',
      );
      final remoteTypes =
          (typesResponse['types'] as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .map((entry) => entry['type'])
              .whereType<String>()
              .toSet();
      expect(
        remoteTypes,
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      for (var i = 0; i < yoloitdPanelTypes.length; i++) {
        final type = yoloitdPanelTypes[i]['type'] as String;
        final panelId = 'docker-panel-$i';
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        final createdPanel = await harness.json(
          'POST',
          '/api/boards/$boardId/panels',
          body: {
            'id': panelId,
            'type': type,
            'title': 'Remote $type',
            'x': 80 + (i % 4) * 360,
            'y': 80 + (i ~/ 4) * 280,
            'width': size['width'],
            'height': size['height'],
            'state': remoteWidgetSmokeState(type),
          },
        );
        expect(createdPanel['ok'], isTrue, reason: type);

        for (final action in remoteWidgetSmokeActions(type)) {
          final response = await harness.json(
            'POST',
            '/api/boards/$boardId/panels/$panelId/action',
            body: action,
          );
          expect(response['ok'], isTrue, reason: '$type ${action['action']}');
        }

        final update = await harness.json(
          'PUT',
          '/api/boards/$boardId/panels/$panelId',
          body: {'width': 444, 'height': 333},
        );
        expect(update['ok'], isTrue, reason: type);

        final fetched = await harness.json(
          'GET',
          '/api/boards/$boardId/panels/$panelId',
        );
        expect(fetched['type'], type);
        _expectRemoteActionState(
          type,
          fetched['content'] as Map<String, dynamic>,
        );
        final bounds = fetched['bounds'] as Map<String, dynamic>;
        expect(bounds['width'], 444, reason: type);
        expect(bounds['height'], 333, reason: type);
      }

      final boardJson = await harness.json('GET', '/api/boards/$boardId');
      expect(boardJson['panels'], hasLength(yoloitdPanelTypes.length));
      final panelTypes =
          (boardJson['panels'] as List<dynamic>)
              .whereType<Map<dynamic, dynamic>>()
              .map((panel) => panel['type'])
              .whereType<String>()
              .toSet();
      expect(
        panelTypes,
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      final snapshot = await harness.text(
        'GET',
        '/api/boards/$boardId/snapshot',
      );
      for (final entry in yoloitdPanelTypes) {
        expect(snapshot, contains(entry['type'] as String));
      }
    },
    skip:
        runDocker
            ? false
            : 'Set YOLOIT_RUN_DOCKER_TESTS=1 to run Docker smoke test.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}

void _expectRemoteActionState(String type, Map<String, dynamic> content) {
  switch (type) {
    case 'board.note.markdown':
      expect(content['markdown'], contains('Appended over remote'));
    case 'board.sticky':
      expect(content['color'], '#F472B6');
    case 'board.shape':
      expect(content['shape'], 'triangle');
    case 'board.kanban':
      expect(
        (content['cards'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .any((card) => card['id'] == 'remote-card-1'),
        isTrue,
      );
    case 'board.webpage':
      expect(content['url'], 'https://example.org');
    case 'board.code.snippet':
      expect(content['language'], 'python');
    case 'board.checklist':
      expect(
        (content['items'] as List<dynamic>)
            .whereType<Map<String, dynamic>>()
            .any(
              (item) => item['id'] == 'remote-item-2' && item['done'] == true,
            ),
        isTrue,
      );
    case 'board.files':
      expect(content['selectedPath'], '/data');
    case 'board.file.preview':
      expect(content['path'], '/data/TODO.md');
    case 'board.playlist':
      expect(content['tracks'], isNotEmpty);
    case 'board.run':
    case 'board.run_configs':
      expect(content['activeSessionId'], 'session-remote');
    case 'board.setup_guide':
      expect(content['selectedPackageIds'], contains('node'));
    case 'board.chat':
      expect(content['messages'], isNotEmpty);
    case 'board.terminal':
      expect((content['config'] as Map)['workingDir'], '/workspace');
    case 'board.filetree':
      expect(content['selectedFile'], '/workspace/lib/main.dart');
    case 'board.diff.preview':
      expect(content['filePath'], '/workspace/lib/main.dart');
    case 'board.yolo_assistant':
      expect(content['assistantStatus'], 'ready');
    case 'board.widget.custom':
      expect(content['widgetId'], 'remote-widget');
    case 'board.timer':
      expect(content['duration'], 900);
    case 'board.table':
      final columns = (content['columns'] as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
      final rows = content['rows'] as List<dynamic>;
      expect(
        columns.map((column) => column['id']).toSet(),
        contains('region'),
      );
      expect(rows, hasLength(2));
      expect(
        rows.whereType<Map<String, dynamic>>().any(
          (row) => row['month'] == 'January',
        ),
        isTrue,
      );
    case 'board.calendar':
      expect(content['view'], 'week');
      final events = content['events'] as List<dynamic>;
      expect(events, isNotEmpty);
      expect(
        events.whereType<Map<String, dynamic>>().any(
          (event) => event['title'] == 'Remote standup',
        ),
        isTrue,
      );
    case 'board.chart':
      expect(content['type'], 'bar');
      final data = content['data'] as List<dynamic>;
      expect(data, hasLength(2));
      expect(
        data.whereType<Map<String, dynamic>>().any(
          (point) => point['month'] == 'Apr',
        ),
        isTrue,
      );
  }
}
