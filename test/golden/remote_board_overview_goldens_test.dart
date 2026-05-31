import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

class _SeededBoardCubit extends BoardCubit {
  _SeededBoardCubit(BoardState state) {
    emit(state);
  }

  @override
  Future<void> refreshRemoteBoards({String? url}) async {}
}

BoardPanelInstance _panel({
  required String id,
  required String title,
  required double x,
  required double y,
  required String color,
}) {
  return BoardPanelInstance(
    id: id,
    type: MarkdownNotePlugin.kTypeId,
    title: title,
    bounds: BoardPanelBounds(x: x, y: y, width: 280, height: 180),
    color: Color(int.parse(color.replaceFirst('#', '0xFF'))),
    state: const {'markdown': '## Remote ready\n- shared board'},
  );
}

BoardDocument _localBoard() {
  return BoardDocument(
    id: 'local-alpha',
    name: 'Local Alpha',
    viewport: const BoardViewport(scale: 0.8, translation: Offset(260, 150)),
    panels: [
      _panel(
        id: 'local-note',
        title: 'Local note',
        x: 20,
        y: 20,
        color: '#111827',
      ),
    ],
  );
}

BoardDocument _remoteBoard() {
  return BoardDocument(
    id: 'remote_demo_remote-shared',
    name: 'Remote Shared',
    viewport: const BoardViewport(scale: 0.75, translation: Offset(240, 160)),
    metadata: const {
      'remote': {
        'url': 'http://remote.yoloit.test:43110/',
        'boardId': 'remote-shared',
        'revision': 7,
      },
      'remoteSource': 'yoloitd',
    },
    panels: [
      BoardPanelInstance(
        id: 'remote-shape',
        type: ShapePlugin.kTypeId,
        title: 'Decision',
        bounds: const BoardPanelBounds(x: 80, y: 30, width: 260, height: 180),
        state: {
          ...const ShapePlugin().initialState,
          'shape': 'diamond',
          'text': 'Remote',
          'strokeColor': '#93C5FD',
          'fillColor': '#1F2937',
          'textColor': '#E5E7EB',
        },
      ),
    ],
  );
}

Widget _harness(BoardCubit cubit) {
  return BlocProvider<BoardCubit>.value(
    value: cubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: BoardView(skipOverviewPreviewCapture: true)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const recordChannel = MethodChannel('com.llfbandit.record/messages');

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, (call) async {
          switch (call.method) {
            case 'create':
              return 1;
            case 'dispose':
            case 'hasPermission':
            case 'isRecording':
            case 'isPaused':
              return false;
            default:
              return null;
          }
        });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(recordChannel, null);
  });

  testGoldens('board overview groups local and remote boards', (tester) async {
    final cubit = _SeededBoardCubit(
      BoardState(
        boards: [_localBoard(), _remoteBoard()],
        activeBoardId: 'local-alpha',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);

    await tester.pumpWidgetBuilder(
      _harness(cubit),
      surfaceSize: const Size(1280, 820),
    );
    await tester.pump();

    await tester.tap(find.byTooltip('Open boards overview'));
    await tester.pump(const Duration(seconds: 8));
    await tester.pump(const Duration(milliseconds: 420));
    await tester.pump();

    expect(find.text('Local boards'), findsOneWidget);
    expect(find.text('Remote boards'), findsOneWidget);
    expect(find.text('Remote Shared'), findsOneWidget);
    expect(find.byIcon(Icons.cloud_outlined), findsWidgets);

    await screenMatchesGolden(tester, 'board_overview_remote_group');
  });
}
