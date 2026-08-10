import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/remote/board_share_server.dart';
import 'package:yoloit/core/ui/adaptive_dialog.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

import 'board_view_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(installBoardViewChannelMocks);
  tearDownAll(removeBoardViewChannelMocks);

  testWidgets('shape catalog entry creates a frame panel', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('Miro basics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Shape / Frame'), findsOneWidget);

    await tester.tap(find.text('Shape / Frame'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final panels = cubit.state.activeBoard!.panels;
    expect(
      panels.any((p) => p.type == 'board.shape' && p.title == 'Frame'),
      isTrue,
    );
  });

  testWidgets('plugin catalog entry falls through to generic panel creation', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('Miro basics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Sticky Note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      cubit.state.activeBoard!.panels.any((p) => p.type == 'board.sticky'),
      isTrue,
    );
  });

  testWidgets('connector tool values update tool and connect settings', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state =
        tester.state(find.byType(BoardView)) as dynamic; // ignore: avoid_dynamic_calls
    final context = tester.element(find.byType(BoardView));

    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__connector:straight:line');
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect(state.debugActiveTool, BoardToolId.connect);
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.geometry, BoardLinkGeometry.straight);
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.showArrow, isFalse);

    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__connector:elbow:arrow');
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.geometry, BoardLinkGeometry.elbow);
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.showArrow, isTrue);

    // Unknown geometry falls back to bezier and defaults to an arrow.
    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__connector:wavy');
    await tester.pump();
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.geometry, BoardLinkGeometry.bezier);
    // ignore: avoid_dynamic_calls
    expect(state.debugConnectSettings.showArrow, isTrue);
  });

  testWidgets('divider and shape variants create titled shape panels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    final state =
        tester.state(find.byType(BoardView)) as dynamic; // ignore: avoid_dynamic_calls
    final context = tester.element(find.byType(BoardView));

    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__divider');
    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__shape:circle');
    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__shape:diamond');
    // ignore: avoid_dynamic_calls
    state.debugHandleGenericToolSelection(context, '__shape:hexagon');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final panels = cubit.state.activeBoard!.panels;
    bool hasShape(String title) =>
        panels.any((p) => p.type == 'board.shape' && p.title == title);
    expect(hasShape('Divider'), isTrue);
    expect(hasShape('Oval'), isTrue);
    expect(hasShape('Rhombus'), isTrue);
    expect(hasShape('Hexagon'), isTrue);
  });

  testWidgets('connect tool creates a styled link between two panels', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final board = boardTestBoard(
      panels: [
        boardTestNote('p1', 'Source'),
        boardTestNote('p2', 'Target', x: 640, width: 260, height: 180),
      ],
    );
    final cubit = TestBoardViewCubit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('Connect (C)'));
    await tester.pump();
    expect(find.byIcon(Icons.add_link), findsWidgets);

    // First tap picks the source panel.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    expect(find.textContaining('Cancel connection'), findsOneWidget);

    // Tapping the same panel again cancels the pending connection.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    expect(find.textContaining('Cancel connection'), findsNothing);

    // Source + target opens the style dialog; cancelling creates no link.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('p2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Link style'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(cubit.state.activeBoard!.links, isEmpty);
    expect(find.textContaining('Cancel connection'), findsNothing);

    // Source + target + confirm creates the link.
    await tester.tap(find.byKey(const ValueKey('p1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('p2')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Link style'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final links = cubit.state.activeBoard!.links;
    expect(links, hasLength(1));
    expect(links.single.fromPanelId, 'p1');
    expect(links.single.toPanelId, 'p2');
    expect(links.single.style, BoardLinkStyle.arrow);
    expect(find.textContaining('Cancel connection'), findsNothing);
  });

  testWidgets('fullscreen action zooms the viewport to the panel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final board = boardTestBoard(panels: [boardTestNote('target', 'Article draft')]);
    final cubit = TestBoardViewCubit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('More actions'));
    await tester.pump();
    expect(find.byTooltip('Fullscreen'), findsOneWidget);

    await tester.tap(find.byTooltip('Fullscreen'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // _zoomToPanel targets ~70% screen fill (scale ≈ 1.6 for this panel),
    // clearly above the auto-fit scale (0.95) applied on load.
    expect(
      cubit.state.activeBoard!.viewport.scale,
      greaterThan(1.3),
    );
  });

  testWidgets('rename group dialog renames the group', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final board = boardTestBoard(
      panels: [boardTestNote('p1', 'Grouped note')],
      groups: const [
        BoardPanelGroup(id: 'g1', name: 'Sprint', panelIds: ['p1']),
      ],
    );
    final cubit = TestBoardViewCubit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Rename group'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'QA group',
    );
    await tester.tap(find.text('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(cubit.state.activeBoard!.groups.single.name, 'QA group');
  });

  testWidgets('rename group dialog cancel keeps the group name', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final board = boardTestBoard(
      panels: [boardTestNote('p1', 'Grouped note')],
      groups: const [
        BoardPanelGroup(id: 'g1', name: 'Sprint', panelIds: ['p1']),
      ],
    );
    final cubit = TestBoardViewCubit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.byTooltip('Rename'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Rename group'), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'Discarded',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(cubit.state.activeBoard!.groups.single.name, 'Sprint');
  });

  testWidgets('board settings saves name, folder and archive flag', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    // Extra-wide surface: after saving, the default-folder chip appears in
    // the toolbar and it no longer fits at 1200px (full-width actions row).
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Board settings'), findsOneWidget);

    final settingsFields = find.descendant(
      of: find.byType(AdaptiveDialogScaffold),
      matching: find.byType(TextField),
    );
    await tester.enterText(settingsFields.first, 'Renamed board');
    await tester.enterText(settingsFields.at(1), '/tmp/yolo-boards');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final saved = cubit.state.boards.singleWhere((b) => b.id == 'board');
    expect(saved.name, 'Renamed board');
    expect(saved.defaultFolder, '/tmp/yolo-boards');
    expect(saved.archived, isTrue);
  });

  testWidgets('board settings unarchives an archived board', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(
        boards: [boardTestBoard(archived: true)],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Board settings'), findsOneWidget);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    await tester.tap(find.text('Save'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(cubit.state.boards.singleWhere((b) => b.id == 'board').archived, isFalse);
  });

  testWidgets('board settings cancel leaves the board unchanged', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Board settings'), findsOneWidget);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(AdaptiveDialogScaffold),
            matching: find.byType(TextField),
          )
          .first,
      'Discarded name',
    );
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final saved = cubit.state.boards.singleWhere((b) => b.id == 'board');
    expect(saved.name, 'Board');
    expect(saved.archived, isFalse);
  });

  testWidgets('connect remote success shows snackbar and opens overview', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    cubit.connectResult = const [
      BoardDocument(id: 'remote-1', name: 'Remote One'),
      BoardDocument(id: 'remote-2', name: 'Remote Two'),
    ];
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Remote'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Connect remote YoLoIT'), findsOneWidget);

    await tester.enterText(
      find
          .descendant(
            of: find.byType(AdaptiveDialogScaffold),
            matching: find.byType(TextField),
          )
          .at(1),
      'secret-token',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(cubit.connectedUrl, 'http://127.0.0.1:43110');
    expect(cubit.connectedToken, 'secret-token');
    expect(find.text('Connected 2 remote boards'), findsOneWidget);
    // A successful connect reopens the boards overview.
    expect(find.text('Local boards'), findsOneWidget);
  });

  testWidgets('connect remote failure surfaces an error snackbar', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    cubit.connectError = StateError('server unreachable');
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Remote'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));

    expect(
      find.textContaining('Remote YoLoIT connection failed'),
      findsOneWidget,
    );
    // The overview stays closed on failure.
    expect(find.text('Local boards'), findsNothing);
  });

  testWidgets('connect remote cancel performs no connection', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Remote'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Connect remote YoLoIT'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(cubit.connectedUrl, isNull);
    expect(find.text('Connect remote YoLoIT'), findsNothing);
  });

  testWidgets('delete board confirm replaces it with a fresh default board', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Delete board?'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    // Deleting the last board seeds a replacement default board.
    expect(cubit.state.boards, hasLength(1));
    expect(cubit.state.boards.single.id, isNot('board'));
    expect(cubit.state.boards.single.name, 'Board 1');
    expect(find.text('Delete board?'), findsNothing);
  });

  testWidgets('delete board cancel keeps the board', (tester) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);

    await tester.tap(find.text('Delete'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Delete board?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(cubit.state.boards.single.id, 'board');
    expect(find.text('Delete board?'), findsNothing);
  });

  testWidgets('share board starts the share server and shows the dialog', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    setBoardViewSurface(tester);

    final cubit = TestBoardViewCubit(
      BoardState(boards: [boardTestBoard()], activeBoardId: 'board', isLoaded: true),
    );
    addTearDown(cubit.close);
    await pumpBoardView(tester, cubit);
    expect(BoardShareServer.instance.isRunning, isFalse);

    // The share server binds a real socket: drive the tap and the bind on
    // the real async clock.
    await tester.runAsync(() async {
      await tester.tap(find.text('Share'));
      await tester.pump();
      // Allow the real HttpServer bind + LAN host lookup to complete.
      await Future<void>.delayed(const Duration(milliseconds: 500));
      await tester.pump();
    });

    expect(BoardShareServer.instance.isRunning, isTrue);
    expect(find.text('Share board'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Share board'), findsNothing);

    // Stop the server on the real clock so no socket leaks past the test.
    await tester.runAsync(() => BoardShareServer.instance.stop());
    expect(BoardShareServer.instance.isRunning, isFalse);
  });
}
