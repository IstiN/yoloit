import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/services/board_preview_cache.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

/// Seeded cubit with remote refresh stubbed out so overview tests stay
/// offline and deterministic.
class _TestBoardCubit extends BoardCubit {
  _TestBoardCubit(BoardState state) {
    emit(state);
  }

  @override
  Future<void> refreshRemoteBoards({String? url}) async {}
}

BoardPanelInstance _note(String id, {bool hidden = false}) {
  return BoardPanelInstance(
    id: id,
    type: MarkdownNotePlugin.kTypeId,
    title: 'Note $id',
    bounds: const BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
    hidden: hidden,
    state: {'markdown': 'content of $id'},
  );
}

BoardDocument _board(
  String id, {
  List<BoardPanelInstance>? panels,
}) {
  return BoardDocument(
    id: id,
    name: 'Board $id',
    viewport: const BoardViewport(scale: 1),
    panels: panels ?? [_note('$id-note')],
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

  Future<void> pumpBoard(
    WidgetTester tester,
    BoardCubit cubit,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            // The overview opens without auto-capturing; the tests drive the
            // capture pipeline explicitly via the view state.
            child: const BoardView(skipOverviewPreviewCapture: true),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('warm captures render and cache previews for all boards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final activeId = 'warm-active-$stamp';
    final otherId = 'warm-other-$stamp';
    final hiddenOnlyId = 'warm-hidden-$stamp';
    final cache = BoardPreviewCache.instance;

    final cubit = _TestBoardCubit(
      BoardState(
        boards: [
          _board(activeId),
          _board(otherId),
          _board(hiddenOnlyId, panels: [_note('$hiddenOnlyId-note', hidden: true)]),
        ],
        activeBoardId: activeId,
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoard(tester, cubit);

    await tester.tap(find.byTooltip('Open boards overview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Local boards'), findsOneWidget);

    final state =
        tester.state(find.byType(BoardView)) as dynamic; // ignore: avoid_dynamic_calls
    await tester.runAsync(() async {
      // ignore: avoid_dynamic_calls
      await state.debugWarmBoardPreviewCaptures(activeId);
    });
    await tester.pump();

    // Active board: captured by _captureBoardPreviewPng.
    expect(cache.pngFile(activeId).existsSync(), isTrue);
    // Other visible board: captured by _generateMissingBoardPreviews.
    expect(cache.pngFile(otherId).existsSync(), isTrue);
    // Hidden-only board: offscreen render returns null, nothing cached even
    // though _refreshPreviewForBoard visited it.
    expect(cache.pngFile(hiddenOnlyId).existsSync(), isFalse);
    // The overview survived the capture pipeline.
    expect(find.text('Local boards'), findsOneWidget);
  });

  testWidgets('background refresh re-captures stale previews', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final activeId = 'refresh-active-$stamp';
    final otherId = 'refresh-other-$stamp';
    final cache = BoardPreviewCache.instance;

    final cubit = _TestBoardCubit(
      BoardState(
        boards: [_board(activeId), _board(otherId)],
        activeBoardId: activeId,
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoard(tester, cubit);

    await tester.tap(find.byTooltip('Open boards overview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final state =
        tester.state(find.byType(BoardView)) as dynamic; // ignore: avoid_dynamic_calls
    await tester.runAsync(() async {
      // ignore: avoid_dynamic_calls
      await state.debugWarmBoardPreviewCaptures(activeId);
    });
    await tester.pump();
    expect(cache.metaFile(otherId).existsSync(), isTrue);

    // Make the cached preview stale, then run the background refresh loop:
    // it must re-render the board and persist a fresh preview.
    cache.metaFile(otherId).deleteSync();
    await tester.runAsync(() async {
      // ignore: avoid_dynamic_calls
      await state.debugRefreshBoardPreviewsInBackground(activeId);
    });
    await tester.pump();

    expect(cache.metaFile(otherId).existsSync(), isTrue);
    expect(cache.pngFile(otherId).existsSync(), isTrue);
  });

  testWidgets('warm capture returns early when the overview is closed', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final activeId = 'closed-active-$stamp';
    final otherId = 'closed-other-$stamp';
    final cache = BoardPreviewCache.instance;

    final cubit = _TestBoardCubit(
      BoardState(
        boards: [_board(activeId), _board(otherId)],
        activeBoardId: activeId,
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoard(tester, cubit);

    // Overview never opened: only the active board is captured, the
    // generate/refresh phases return immediately.
    final state =
        tester.state(find.byType(BoardView)) as dynamic; // ignore: avoid_dynamic_calls
    await tester.runAsync(() async {
      // ignore: avoid_dynamic_calls
      await state.debugWarmBoardPreviewCaptures(activeId);
    });
    await tester.pump();

    expect(cache.pngFile(activeId).existsSync(), isTrue);
    expect(cache.pngFile(otherId).existsSync(), isFalse);
  });
}
