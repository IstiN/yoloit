import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/app_mobile.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PlatformDirs.setInstance(const IosPlatformDirs(homeOverride: '/ios/app'));
  });

  tearDown(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  testWidgets('mobile board app starts without desktop shell', (tester) async {
    await tester.pumpWidget(const MobileBoardApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Board 1'), findsOneWidget);
    expect(find.byIcon(Icons.add), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile board app can auto-connect remote boards', (
    tester,
  ) async {
    final cubit = _FakeMobileBoardCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(
      MobileBoardApp(
        boardCubit: cubit,
        initialRemoteUrl: 'http://127.0.0.1:43110',
        initialRemoteToken: 'secret',
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(cubit.connectCalls, 1);
    expect(find.text('Remote Mobile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile board app fits an iPhone-sized viewport', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = _FakeMobileBoardCubit();
    addTearDown(cubit.close);

    await tester.pumpWidget(MobileBoardApp(boardCubit: cubit));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Board 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeMobileBoardCubit extends BoardCubit {
  _FakeMobileBoardCubit() : super();

  int connectCalls = 0;

  @override
  Future<void> load() async {
    emit(
      const BoardState(
        boards: [BoardDocument(id: 'local-board', name: 'Board 1')],
        activeBoardId: 'local-board',
        isLoaded: true,
      ),
    );
  }

  @override
  Future<List<BoardDocument>> connectRemoteBoards({
    required String url,
    String? token,
  }) async {
    connectCalls += 1;
    const remote = BoardDocument(
      id: 'remote-board',
      name: 'Remote Mobile',
      metadata: {
        'remote': {
          'url': 'http://127.0.0.1:43110',
          'token': 'secret',
          'boardId': 'remote-board',
          'revision': 1,
        },
      },
    );
    emit(
      const BoardState(
        boards: [remote],
        activeBoardId: 'remote-board',
        isLoaded: true,
      ),
    );
    return const [remote];
  }
}
