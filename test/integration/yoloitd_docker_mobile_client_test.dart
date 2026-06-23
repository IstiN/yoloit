import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

import '../helpers/remote_widget_smoke_data.dart';
import '../helpers/yoloitd_docker_harness.dart';

void main() {
  final runDocker = Platform.environment['YOLOIT_RUN_DOCKER_TESTS'] == '1';

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
    PlatformDirs.setInstance(const IosPlatformDirs(homeOverride: '/ios/app'));
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  test(
    'mobile client connects to docker yoloitd and syncs every remote widget panel',
    () async {
      final harness = await YoloitdDockerHarness.start();
      addTearDown(harness.dispose);

      final created = await harness.json(
        'POST',
        '/api/boards',
        body: {'name': 'Docker Mobile Remote'},
      );
      final boardId =
          (created['board'] as Map<String, dynamic>)['id'] as String;

      for (var i = 0; i < yoloitdPanelTypes.length; i++) {
        final type = yoloitdPanelTypes[i]['type'] as String;
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        await harness.json(
          'POST',
          '/api/boards/$boardId/panels',
          body: {
            'id': 'mobile-panel-$i',
            'type': type,
            'title': 'Mobile $type',
            'x': 60 + (i % 3) * 360,
            'y': 60 + (i ~/ 3) * 280,
            'width': size['width'],
            'height': size['height'],
            'state': remoteWidgetSmokeState(type),
          },
        );
      }

      final cubit = BoardCubit(actorId: 'mobile-docker-test');
      addTearDown(cubit.close);
      await cubit.load();
      final boards = await cubit.connectRemoteBoards(
        url: harness.baseUrl,
        token: harness.token,
      );

      final targetBoard = boards.singleWhere(
        (board) => board.name == 'Docker Mobile Remote',
      );
      await cubit.setActiveBoard(targetBoard.id);

      final active = cubit.state.activeBoard!;
      expect(active.name, 'Docker Mobile Remote');
      expect(active.panels, hasLength(yoloitdPanelTypes.length));
      expect(
        active.panels.map((panel) => panel.type).toSet(),
        containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
      );

      for (final panel in active.panels) {
        await cubit.updatePanel(
          panel.id,
          (current) => current.copyWith(
            bounds: current.bounds.copyWith(
              x: current.bounds.x + 11,
              y: current.bounds.y + 13,
              width: current.bounds.width + 23,
              height: current.bounds.height + 19,
            ),
          ),
        );
      }
      await cubit.flushRemoteSync();

      final serverBoard = await harness.json('GET', '/api/boards/$boardId');
      final panels =
          (serverBoard['panels'] as List<dynamic>)
              .whereType<Map<String, dynamic>>()
              .toList();
      expect(panels, hasLength(yoloitdPanelTypes.length));
      for (var i = 0; i < panels.length; i++) {
        final size =
            yoloitdPanelTypes[i]['defaultSize'] as Map<String, dynamic>;
        final bounds = panels[i]['bounds'] as Map<String, dynamic>;
        expect(bounds['x'], 60 + (i % 3) * 360 + 11);
        expect(bounds['y'], 60 + (i ~/ 3) * 280 + 13);
        expect(bounds['width'], (size['width'] as num).toDouble() + 23);
        expect(bounds['height'], (size['height'] as num).toDouble() + 19);
      }
    },
    skip:
        runDocker
            ? false
            : 'Set YOLOIT_RUN_DOCKER_TESTS=1 to run Docker smoke test.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
