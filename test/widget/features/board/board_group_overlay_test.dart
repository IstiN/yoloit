import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_group_overlay.dart';

BoardPanelInstance _panel(String id, double x, double y) {
  return BoardPanelInstance(
    id: id,
    type: 'board.note.markdown',
    title: id,
    bounds: BoardPanelBounds(x: x, y: y, width: 200, height: 120),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The collapsed group stack: x=100, y=100, w=300, h=200 with origin zero.
  // Background rect: left=84, top=56, width=332, height=260.
  const stackBounds = BoardPanelBounds(x: 100, y: 100, width: 300, height: 200);
  const startRect = Rect.fromLTWH(100, 100, 300, 200);

  BoardDocument boardWithCollapsedGroup() {
    return BoardDocument(
      id: 'board',
      name: 'Board',
      panels: [_panel('p1', 100, 100), _panel('p2', 100, 100)],
      groups: const [
        BoardPanelGroup(
          id: 'g1',
          name: 'Collapsed group',
          panelIds: ['p1', 'p2'],
          collapsed: true,
          collapsedBounds: stackBounds,
        ),
      ],
    );
  }

  Widget buildOverlay({
    required BoardDocument board,
    void Function(String groupId, BoardPanelBounds newBounds)? onResize,
    ValueChanged<String>? onToggleCollapse,
    ValueChanged<String>? onRenameGroup,
    void Function(String groupId, int direction)? onCycleFocus,
    void Function(String groupId, DragUpdateDetails details)? onMoveGroup,
    ValueChanged<String>? onMoveGroupStart,
    ValueChanged<String>? onMoveGroupEnd,
  }) {
    return MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(
          width: 900,
          height: 700,
          child: BoardGroupOverlay(
            board: board,
            origin: Offset.zero,
            onToggleCollapse: onToggleCollapse ?? (_) {},
            onMoveGroup: onMoveGroup ?? (_, _) {},
            onMoveGroupStart: onMoveGroupStart ?? (_) {},
            onMoveGroupEnd: onMoveGroupEnd ?? (_) {},
            onRenameGroup: onRenameGroup ?? (_) {},
            onCycleFocus: onCycleFocus ?? (_, _) {},
            onResizeCollapsedGroup: onResize ?? (_, _) {},
          ),
        ),
      ),
    );
  }

  Future<void> pumpOverlay(
    WidgetTester tester, {
    required BoardDocument board,
    void Function(String groupId, BoardPanelBounds newBounds)? onResize,
    ValueChanged<String>? onToggleCollapse,
    ValueChanged<String>? onRenameGroup,
    void Function(String groupId, int direction)? onCycleFocus,
    void Function(String groupId, DragUpdateDetails details)? onMoveGroup,
    ValueChanged<String>? onMoveGroupStart,
    ValueChanged<String>? onMoveGroupEnd,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      buildOverlay(
        board: board,
        onResize: onResize,
        onToggleCollapse: onToggleCollapse,
        onRenameGroup: onRenameGroup,
        onCycleFocus: onCycleFocus,
        onMoveGroup: onMoveGroup,
        onMoveGroupStart: onMoveGroupStart,
        onMoveGroupEnd: onMoveGroupEnd,
      ),
    );
    await tester.pump();
  }

  Future<Rect> dragHandle(
    WidgetTester tester,
    List<Rect> reported,
    Offset handleCenter,
    Offset delta,
  ) async {
    reported.clear();
    final gesture = await tester.startGesture(handleCenter);
    await gesture.moveBy(delta);
    await gesture.up();
    await tester.pump();
    expect(reported, isNotEmpty, reason: 'handle at $handleCenter did not drag');
    return reported.last;
  }

  group('collapsed group resize handles', () {
    // Handle centers derived from the background rect (84, 56, 332, 260).
    testWidgets('corner handles resize both axes', (tester) async {
      final reported = <Rect>[];
      await pumpOverlay(
        tester,
        board: boardWithCollapsedGroup(),
        onResize: (_, bounds) => reported.add(
          Rect.fromLTWH(bounds.x, bounds.y, bounds.width, bounds.height),
        ),
      );

      // topLeft: dragging down-right shrinks from the top-left corner.
      var rect = await dragHandle(
        tester,
        reported,
        const Offset(88, 60),
        const Offset(80, 60),
      );
      expect(rect.left, greaterThan(startRect.left));
      expect(rect.top, greaterThan(startRect.top));
      expect(rect.width, lessThan(startRect.width));
      expect(rect.height, lessThan(startRect.height));

      // topRight: grows width, shrinks height, left edge fixed.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(412, 60),
        const Offset(80, 60),
      );
      expect(rect.left, startRect.left);
      expect(rect.top, greaterThan(startRect.top));
      expect(rect.width, greaterThan(startRect.width));
      expect(rect.height, lessThan(startRect.height));

      // bottomLeft: shrinks width, grows height, top edge fixed.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(88, 312),
        const Offset(80, 60),
      );
      expect(rect.left, greaterThan(startRect.left));
      expect(rect.top, startRect.top);
      expect(rect.width, lessThan(startRect.width));
      expect(rect.height, greaterThan(startRect.height));

      // bottomRight: grows both axes, top-left fixed.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(412, 312),
        const Offset(80, 60),
      );
      expect(rect.left, startRect.left);
      expect(rect.top, startRect.top);
      expect(rect.width, greaterThan(startRect.width));
      expect(rect.height, greaterThan(startRect.height));
    });

    testWidgets('edge handles resize a single axis', (tester) async {
      final reported = <Rect>[];
      await pumpOverlay(
        tester,
        board: boardWithCollapsedGroup(),
        onResize: (_, bounds) => reported.add(
          Rect.fromLTWH(bounds.x, bounds.y, bounds.width, bounds.height),
        ),
      );

      // top edge: only top/height change.
      var rect = await dragHandle(
        tester,
        reported,
        const Offset(250, 60),
        const Offset(0, 60),
      );
      expect(rect.left, startRect.left);
      expect(rect.width, startRect.width);
      expect(rect.top, greaterThan(startRect.top));
      expect(rect.height, lessThan(startRect.height));

      // bottom edge: only height changes.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(250, 312),
        const Offset(0, 60),
      );
      expect(rect.left, startRect.left);
      expect(rect.top, startRect.top);
      expect(rect.width, startRect.width);
      expect(rect.height, greaterThan(startRect.height));

      // left edge: only left/width change.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(88, 186),
        const Offset(80, 0),
      );
      expect(rect.top, startRect.top);
      expect(rect.height, startRect.height);
      expect(rect.left, greaterThan(startRect.left));
      expect(rect.width, lessThan(startRect.width));

      // right edge: only width changes.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(412, 186),
        const Offset(80, 0),
      );
      expect(rect.left, startRect.left);
      expect(rect.top, startRect.top);
      expect(rect.height, startRect.height);
      expect(rect.width, greaterThan(startRect.width));
    });

    testWidgets('size clamps at the minimum width and height', (tester) async {
      final reported = <Rect>[];
      await pumpOverlay(
        tester,
        board: boardWithCollapsedGroup(),
        onResize: (_, bounds) => reported.add(
          Rect.fromLTWH(bounds.x, bounds.y, bounds.width, bounds.height),
        ),
      );

      // Dragging the left edge far past the right edge clamps the width.
      var rect = await dragHandle(
        tester,
        reported,
        const Offset(88, 186),
        const Offset(500, 0),
      );
      expect(rect.width, 80);

      // Dragging the top edge far past the bottom edge clamps the height.
      rect = await dragHandle(
        tester,
        reported,
        const Offset(250, 60),
        const Offset(0, 500),
      );
      expect(rect.height, 60);
    });
  });

  group('group headers', () {
    testWidgets('expanded group shows header and fires header callbacks', (
      tester,
    ) async {
      String? toggled;
      String? renamed;
      String? moveStarted;
      String? moveEnded;
      var moved = 0;
      final board = BoardDocument(
        id: 'board',
        name: 'Board',
        panels: [_panel('p1', 100, 100), _panel('p2', 400, 300)],
        groups: const [
          BoardPanelGroup(id: 'g1', name: 'Team A', panelIds: ['p1', 'p2']),
          BoardPanelGroup(id: 'g2', name: 'Empty group'),
        ],
      );
      await pumpOverlay(
        tester,
        board: board,
        onToggleCollapse: (id) => toggled = id,
        onRenameGroup: (id) => renamed = id,
        onMoveGroupStart: (id) => moveStarted = id,
        onMoveGroupEnd: (id) => moveEnded = id,
        onMoveGroup: (_, _) => moved++,
      );

      // Only the non-empty group renders a header.
      expect(find.text('Team A'), findsOneWidget);
      expect(find.text('(2)'), findsOneWidget);
      expect(find.text('Empty group'), findsNothing);

      await tester.tap(find.byTooltip('Collapse'));
      await tester.pump();
      expect(toggled, 'g1');

      await tester.tap(find.byTooltip('Rename'));
      await tester.pump();
      expect(renamed, 'g1');

      // Dragging the header moves the whole group.
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Team A')),
      );
      await gesture.moveBy(const Offset(60, 40));
      await gesture.up();
      await tester.pump();
      expect(moveStarted, 'g1');
      expect(moved, greaterThan(0));
      expect(moveEnded, 'g1');
    });

    testWidgets('collapsed group with several panels cycles focus', (
      tester,
    ) async {
      final cycles = <int>[];
      String? toggled;
      await pumpOverlay(
        tester,
        board: boardWithCollapsedGroup(),
        onCycleFocus: (_, direction) => cycles.add(direction),
        onToggleCollapse: (id) => toggled = id,
      );

      expect(find.text('Collapsed group'), findsOneWidget);

      await tester.tap(find.byTooltip('Next panel'));
      await tester.pump();
      await tester.tap(find.byTooltip('Previous panel'));
      await tester.pump();
      expect(cycles, [1, -1]);

      await tester.tap(find.byTooltip('Expand'));
      await tester.pump();
      expect(toggled, 'g1');
    });
  });
}
