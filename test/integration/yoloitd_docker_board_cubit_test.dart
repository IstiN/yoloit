import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';

import '../helpers/remote_widget_smoke_data.dart';
import '../helpers/yoloitd_docker_harness.dart';

void main() {
  final runDocker = Platform.environment['YOLOIT_RUN_DOCKER_TESTS'] == '1';

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'BoardCubit connects to docker yoloitd and syncs every remote widget panel',
    () async {
      final harness = await YoloitdDockerHarness.start();
      addTearDown(harness.dispose);

      final created = await harness.json(
        'POST',
        '/api/boards',
        body: {'name': 'Docker BoardCubit Remote'},
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
            'id': 'client-panel-$i',
            'type': type,
            'title': 'Remote $type',
            'x': 80 + (i % 4) * 360,
            'y': 80 + (i ~/ 4) * 280,
            'width': size['width'],
            'height': size['height'],
            'state': remoteWidgetSmokeState(type),
          },
        );
      }

      final cubit = BoardCubit(actorId: 'mac-client-test');
      addTearDown(cubit.close);
      await cubit.load();
      final boards = await cubit.connectRemoteBoards(
        url: harness.baseUrl,
        token: harness.token,
      );

      expect(boards, hasLength(greaterThanOrEqualTo(1)));
      final targetBoard = boards.singleWhere(
        (board) => board.name == 'Docker BoardCubit Remote',
      );
      await cubit.setActiveBoard(targetBoard.id);
      expect(
        cubit.state.activeBoard!.panels,
        hasLength(yoloitdPanelTypes.length),
      );

      for (final panel in cubit.state.activeBoard!.panels) {
        await cubit.updatePanel(
          panel.id,
          (current) => current.copyWith(
            bounds: current.bounds.copyWith(
              width: current.bounds.width + 17,
              height: current.bounds.height + 9,
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
        expect(bounds['width'], (size['width'] as num).toDouble() + 17);
        expect(bounds['height'], (size['height'] as num).toDouble() + 9);
      }
    },
    skip:
        runDocker
            ? false
            : 'Set YOLOIT_RUN_DOCKER_TESTS=1 to run Docker smoke test.',
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
