import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

import 'board_view_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  tearDown(() {
    BoardView.debugDisablePreviewOverlayForTesting = false;
  });

  BoardDocument makeBoard(String id, {String name = ''}) {
    return BoardDocument(
      id: id,
      name: name.isEmpty ? 'Board $id' : name,
      viewport: const BoardViewport(scale: 1),
    );
  }

  BoardState stateWith(List<String> ids, {String active = 'a'}) {
    return BoardState(
      boards: ids.map(makeBoard).toList(growable: false),
      activeBoardId: active,
      isLoaded: true,
    );
  }

  group('BoardSwitchPreviewOverlay', () {
    testWidgets('fade duration is now 80ms (was 260ms)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoardSwitchPreviewOverlay(
              board: const BoardDocument(id: 'x', name: 'X'),
              previewPng: null,
              visible: true,
              onHidden: () {},
            ),
          ),
        ),
      );

      final animated = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(
        animated.duration,
        const Duration(milliseconds: 80),
        reason: 'Per TDD Step 2: fade must be <= 100ms.',
      );
      expect(
        animated.duration.inMilliseconds,
        lessThanOrEqualTo(100),
      );
    });

    testWidgets('onHidden is not invoked after the widget is unmounted',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);

      var hiddenCalled = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BoardSwitchPreviewOverlay(
              board: const BoardDocument(id: 'x', name: 'X'),
              previewPng: null,
              visible: true,
              onHidden: () => hiddenCalled = true,
            ),
          ),
        ),
      );
      // Tear the overlay down before the fade completes.
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: SizedBox.shrink()),
        ),
      );
      // Pump several frames worth of time so any pending animation would
      // have completed by now.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();

      expect(
        hiddenCalled,
        isFalse,
        reason: 'onHidden must never run after the overlay is unmounted.',
      );
    });
  });

  group('BoardView.onSelectedBoard', () {
    late BoardCubit cubit;

    Future<void> pumpCubit(WidgetTester tester, BoardCubit c) async {
      await pumpBoardView(tester, c);
    }

    setUp(() {
      cubit = TestBoardViewCubit(stateWith(const ['a', 'b', 'c', 'd', 'e']));
    });

    tearDown(() async {
      await cubit.close();
    });

    testWidgets(
        'rapid successive switches coalesce into a single fade-out timer',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);
      await pumpCubit(tester, cubit);

      // ignore: avoid_dynamic_calls
      final state = tester.state(find.byType(BoardView)) as dynamic;
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 0);

      for (final id in const ['b', 'c', 'd', 'e']) {
        final board = cubit.state.boards
            .firstWhere((BoardDocument b) => b.id == id);
        // ignore: avoid_dynamic_calls
        state.debugSimulateBoardSelection(board, null);
      }

      // Only the LAST preview is the one that gets to actually start its
      // fade-out timer; the previous 4 are dropped because the pending timer
      // is cancelled on each new request.
      // ignore: avoid_dynamic_calls
      expect(state.debugBoardSwitchPreviewBoard?.id, 'e');
      // No timer has fired yet — we're still inside the 80ms window.
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 0);

      // Pump until just shy of the 80ms boundary.
      await tester.pump(const Duration(milliseconds: 79));
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 0);
      // ignore: avoid_dynamic_calls
      expect(state.debugIsBoardSwitchPreviewVisible, isTrue);

      // Cross the 80ms boundary — exactly ONE fade-out should fire now.
      await tester.pump(const Duration(milliseconds: 2));
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 1);
      // ignore: avoid_dynamic_calls
      expect(state.debugIsBoardSwitchPreviewVisible, isFalse);

      // Pumping further must not schedule more fade-out callbacks.
      await tester.pump(const Duration(milliseconds: 500));
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 1);
    });

    testWidgets(
        'debugDisablePreviewOverlayForTesting skips the preview entirely',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      setBoardViewSurface(tester);
      await pumpCubit(tester, cubit);
      BoardView.debugDisablePreviewOverlayForTesting = true;

      // ignore: avoid_dynamic_calls
      final state = tester.state(find.byType(BoardView)) as dynamic;
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 0);
      final board = cubit.state.boards
          .firstWhere((BoardDocument b) => b.id == 'b');
      // ignore: avoid_dynamic_calls
      state.debugSimulateBoardSelection(board, null);

      // The preview state must remain untouched: no fade-out ever fires.
      // ignore: avoid_dynamic_calls
      expect(state.debugBoardSwitchPreviewBoard, isNull);
      // ignore: avoid_dynamic_calls
      expect(state.debugIsBoardSwitchPreviewVisible, isFalse);

      // No timer should fire either.
      await tester.pump(const Duration(milliseconds: 200));
      // ignore: avoid_dynamic_calls
      expect(state.debugFadeOutCount, 0);
    });
  });
}
