import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_grid_mode.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_layer.dart';
import 'package:yoloit/features/board/ui/unified_panel_header.dart';

import 'board_view_test_harness.dart';

/// Exercises the multi-select marquee overlay, the selection-to-group flow,
/// grid-mode drag commits, and the board overview layer of `BoardView`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  Future<TestBoardViewCubit> pumpSeededBoard(
    WidgetTester tester,
    BoardDocument board,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);
    final cubit = TestBoardViewCubit(
      BoardState(boards: [board], activeBoardId: board.id, isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);
    return cubit;
  }

  Future<void> activateMultiSelect(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Select Many (M)'));
    await tester.pump();
  }

  testWidgets('multi-select taps toggle selection, empty tap clears it', (
    tester,
  ) async {
    final cubit = await pumpSeededBoard(
      tester,
      boardTestBoard(
        panels: [
          boardTestNote('p1', 'Alpha'),
          boardTestNote('p2', 'Beta', x: 640),
        ],
      ),
    );
    await activateMultiSelect(tester);

    // Tap on a panel toggles it into the selection.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    expect(cubit.state.selectedPanelIds, {'p1'});
    expect(find.text('1 selected'), findsOneWidget);

    // Tapping the same panel again removes it from the selection.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    expect(cubit.state.selectedPanelIds, isEmpty);

    // A fresh selection is cleared by tapping the empty canvas.
    await tester.tap(find.byKey(const ValueKey('p2')));
    await tester.pump();
    expect(cubit.state.selectedPanelIds, {'p2'});
    await tester.tapAt(const Offset(1100, 640));
    await tester.pump();
    expect(cubit.state.selectedPanelIds, isEmpty);
  });

  testWidgets('multi-select marquee drag selects the panels in the rect', (
    tester,
  ) async {
    final cubit = await pumpSeededBoard(
      tester,
      boardTestBoard(
        panels: [
          boardTestNote('p1', 'Alpha'),
          boardTestNote('p2', 'Beta', x: 640),
        ],
      ),
    );
    await activateMultiSelect(tester);

    // Drag a marquee from the empty bottom-right corner up across both
    // panels. Starting on empty canvas matters: a pointer-down inside a
    // panel starts a panel drag instead of a marquee.
    final gesture = await tester.startGesture(const Offset(1140, 700));
    await tester.pump();
    await gesture.moveTo(const Offset(600, 400));
    await tester.pump();
    await gesture.moveTo(const Offset(30, 100));
    await tester.pump();
    await gesture.up();
    await tester.pump();

    expect(cubit.state.selectedPanelIds, {'p1', 'p2'});
    expect(find.text('2 selected'), findsOneWidget);

    // A short tap-like gesture (below the drag threshold) clears instead.
    await tester.tapAt(const Offset(1100, 640));
    await tester.pump();
    expect(cubit.state.selectedPanelIds, isEmpty);
  });

  testWidgets('grid mode drag commits a snap that pushes the neighbour', (
    tester,
  ) async {
    // One pitch is 220 + 24 = 244; both panels sit in row 2 (y = 2 * 244)
    // so the drag happens far from the viewport edges and never triggers
    // edge-panning.
    final cubit = await pumpSeededBoard(
      tester,
      boardTestBoard(
        panels: [
          boardTestNote('p1', 'Cell A', x: 0, y: 488, width: 220, height: 220),
          boardTestNote('p2', 'Cell B', x: 244, y: 488, width: 220, height: 220),
        ],
        metadata: <String, dynamic>{
          'gridView': const BoardGridMode(enabled: true).toJson(),
        },
      ),
    );
    expect(cubit.state.activeBoard!.gridMode.enabled, isTrue);

    // Drag p1's header about three quarters of a pitch to the right: the drop
    // target rounds to p2's cell, so the commit snaps p1 onto it and pushes
    // p2 to cell (2, 2). Step the gesture so the drag recognizer wins the
    // arena over the viewport pan.
    final header = find.descendant(
      of: find.byKey(const ValueKey('p1')),
      matching: find.byType(UnifiedPanelHeader),
    );
    final gesture = await tester.startGesture(tester.getCenter(header));
    await tester.pump();
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final panels = cubit.state.activeBoard!.panels;
    final moved = panels.singleWhere((p) => p.id == 'p1');
    final pushed = panels.singleWhere((p) => p.id == 'p2');
    // The dragged panel snaps exactly to p2's old cell: (1, 2).
    expect(moved.bounds.x, 244.0);
    expect(moved.bounds.y, 488.0);
    // The pushed neighbour snaps exactly to cell (2, 2): x = 2 * 244.
    expect(pushed.bounds.x, 488.0);
    expect(pushed.bounds.y, 488.0);
  });

  testWidgets('selection group dialog: cancel keeps state, name creates group', (
    tester,
  ) async {
    final cubit = await pumpSeededBoard(
      tester,
      boardTestBoard(
        panels: [
          boardTestNote('p1', 'One'),
          boardTestNote('p2', 'Two', x: 640),
        ],
      ),
    );
    cubit.selectPanels({'p1', 'p2'});
    await tester.pump();
    expect(find.text('2 selected'), findsOneWidget);

    // Cancel: the dialog closes without touching groups or the selection.
    await tester.tap(find.text('Add to group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Add selection to group'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(cubit.state.activeBoard!.groups, isEmpty);
    expect(cubit.state.selectedPanelIds, {'p1', 'p2'});

    // New group name: creates a group from the whole selection.
    await tester.tap(find.text('Add to group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'QA Crew',
    );
    // Rebuild so the Add button's closure picks up the entered name.
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final groups = cubit.state.activeBoard!.groups;
    expect(groups.single.name, 'QA Crew');
    expect(groups.single.panelIds, containsAll(<String>['p1', 'p2']));
    expect(cubit.state.selectedPanelIds, isEmpty);
  });

  testWidgets('selection group dialog adds the panels to an existing group', (
    tester,
  ) async {
    final cubit = await pumpSeededBoard(
      tester,
      boardTestBoard(
        panels: [
          boardTestNote('p1', 'Grouped'),
          boardTestNote('p2', 'Loose', x: 640),
        ],
        groups: const [
          BoardPanelGroup(id: 'g1', name: 'Sprint', panelIds: ['p1']),
        ],
      ),
    );
    cubit.selectPanels({'p2'});
    await tester.pump();

    await tester.tap(find.text('Add to group'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Or add to existing group'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Sprint'));
    await tester.pump();
    await tester.tap(find.text('Add'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final group = cubit.state.activeBoard!.groups.single;
    expect(group.panelIds, containsAll(<String>['p1', 'p2']));
    expect(cubit.state.selectedPanelIds, isEmpty);
  });

  testWidgets('board overview switches boards, creates and closes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);
    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [
          boardTestBoard(),
          boardTestBoard(id: 'second', name: 'Second'),
        ],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    Future<void> openOverview() async {
      await tester.tap(find.byTooltip('Open boards overview'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 450));
      expect(find.text('Local boards'), findsOneWidget);
    }

    // Selecting another board closes the overview and switches to it.
    await openOverview();
    await tester.tap(find.text('Second'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(cubit.state.activeBoardId, 'second');
    expect(find.text('Local boards'), findsNothing);
    // Drain the switch-preview fade so no timers leak past the test.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));

    // The close button dismisses the overview without switching.
    await openOverview();
    await tester.tap(find.byTooltip('Close boards overview'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Local boards'), findsNothing);
    expect(cubit.state.activeBoardId, 'second');

    // The create card routes through the blank-board flow. The toolbar also
    // has a 'New board' label, so scope the tap to the overview layer.
    await openOverview();
    await tester.tap(
      find.descendant(
        of: find.byType(BoardOverviewLayer),
        matching: find.text('New board'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Blank board'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    expect(find.text('Create board'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Fresh',
    );
    await tester.pump();
    await tester.tap(find.text('Create'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(cubit.state.boards.any((b) => b.name == 'Fresh'), isTrue);
    // Drain the board-switch preview timers from the creation switch.
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump(const Duration(milliseconds: 600));
  });
}
