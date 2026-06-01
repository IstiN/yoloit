import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/yoloitd_models.dart';
import 'package:yoloit/core/remote/yoloitd_server.dart';
import 'package:yoloit/core/remote/yoloitd_store.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

Widget _remoteBoardHarness(BoardCubit cubit) {
  return BlocProvider<BoardCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: BoardView()),
    ),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    HttpOverrides.global = null;
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('desktop board UI connects to yoloitd and shows remote boards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final dir = await Directory.systemTemp.createTemp('yoloitd_ui_it_');
    addTearDown(() => dir.delete(recursive: true));

    final store = YoloitdStore(rootDir: dir, actorId: 'integration');
    final board = await store.createBoard('Remote Integration');
    await store.addPanel(
      board.id,
      const RemotePanel(
        id: 'remote-note',
        type: 'board.note.markdown',
        title: 'Remote Note',
        bounds: RemotePanelBounds(x: 60, y: 70, width: 320, height: 220),
        state: {'markdown': '## Integration board'},
      ),
    );

    final server = YoloitdServer(store: store, port: 0, token: 'it-token');
    await server.start();
    addTearDown(server.stop);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    await cubit.load();

    await tester.pumpWidget(_remoteBoardHarness(cubit));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();

    await tester.tap(find.text('Remote'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(find.text('Connect remote YoLoIT'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Remote URL'),
      'http://127.0.0.1:${server.boundPort}',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Token'), 'it-token');
    await tester.tap(find.text('Connect').last);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(cubit.state.activeBoard?.name, 'Remote Integration');
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump();

    expect(find.text('Local boards'), findsOneWidget);
    expect(find.text('Remote boards'), findsOneWidget);
    expect(find.text('Remote Integration'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsWidgets);
  });
}
