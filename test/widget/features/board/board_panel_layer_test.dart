import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_panel_floating_chrome.dart';
import 'package:yoloit/features/board/ui/board_panel_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sticky = BoardPanelInstance(
    id: 'sticky-1',
    type: StickyNotePlugin.kTypeId,
    title: 'Sticky',
    bounds: BoardPanelBounds(x: 100, y: 100, width: 260, height: 220),
    zIndex: 1,
    state: {'text': 'Note', 'fontSize': 18.0},
  );
  const note = BoardPanelInstance(
    id: 'note-1',
    type: MarkdownNotePlugin.kTypeId,
    title: 'Note',
    bounds: BoardPanelBounds(x: 500, y: 100, width: 320, height: 240),
    zIndex: 5,
    state: {'markdown': 'hello'},
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  BoardDocument buildBoard({String? focusedPanelId, bool collapsed = false}) {
    return BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1, focusedPanelId: focusedPanelId),
      panels: const [sticky, note],
      groups:
          collapsed
              ? const [
                BoardPanelGroup(
                  id: 'g1',
                  name: 'Group',
                  panelIds: ['sticky-1'],
                  collapsed: true,
                ),
              ]
              : const [],
    );
  }

  Future<BoardCubit> pumpLayer(
    WidgetTester tester, {
    required BoardDocument board,
  }) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    await tester.pumpWidget(
      // BoardCubit sits above the MaterialApp so dialogs pushed onto the root
      // navigator (e.g. PanelSettingsDialog) can also read it.
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: BoardPanelLayer(
              board: board,
              canvasOrigin: Offset.zero,
              isCapturingScreenshot: false,
              selectedPanelIds: const {},
              activeTool: BoardToolId.select,
              connectSourceId: null,
              onMovePanel: (_, _, _) {},
              onResizePanel: (_, _, _) {},
              onDragStart: (_, _) {},
              onDragEnd: () {},
              onConnectTap: (_, _, _) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    return cubit;
  }

  Finder chromeTooltip(String tooltip) {
    return find.descendant(
      of: find.byType(BoardPanelFloatingChrome),
      matching: find.byTooltip(tooltip),
    );
  }

  BoardPanelInstance stickyIn(BoardCubit cubit) {
    return cubit.state.activeBoard!.panels.singleWhere((p) => p.id == 'sticky-1');
  }

  group('floating chrome', () {
    testWidgets('renders for a focused headerless panel and reorders z-index', (
      tester,
    ) async {
      final cubit = await pumpLayer(
        tester,
        board: buildBoard(focusedPanelId: 'sticky-1'),
      );

      // The floating chrome toolbar is visible for the focused sticky note.
      expect(chromeTooltip('Text size'), findsWidgets);

      await tester.tap(chromeTooltip('More actions').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Bring to front').first);
      await tester.pump();
      expect(stickyIn(cubit).zIndex, greaterThan(note.zIndex));

      await tester.tap(chromeTooltip('More actions').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Send to back').first);
      await tester.pump();
      expect(stickyIn(cubit).zIndex, lessThan(note.zIndex));
    });

    testWidgets('updates panel state via the text size menu', (tester) async {
      final cubit = await pumpLayer(
        tester,
        board: buildBoard(focusedPanelId: 'sticky-1'),
      );

      await tester.tap(chromeTooltip('Text size').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.text('24').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(stickyIn(cubit).state['fontSize'], 24.0);
    });

    testWidgets('delete removes the panel from the board', (tester) async {
      final cubit = await pumpLayer(
        tester,
        board: buildBoard(focusedPanelId: 'sticky-1'),
      );

      await tester.tap(chromeTooltip('Remove').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(
        cubit.state.activeBoard!.panels.any((p) => p.id == 'sticky-1'),
        isFalse,
      );
    });

    testWidgets('settings dialog routes to the color picker', (tester) async {
      await pumpLayer(tester, board: buildBoard(focusedPanelId: 'sticky-1'));

      await tester.tap(chromeTooltip('More actions').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.tap(find.byTooltip('Settings').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // PanelSettingsDialog actions.
      expect(find.text('Panel color'), findsOneWidget);
      await tester.tap(find.text('Panel color'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // The inline color dialog opened via the onEditColor callback.
      expect(find.text('Apply'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Apply'), findsNothing);
    });

    testWidgets('is hidden when the focused panel is in a collapsed group', (
      tester,
    ) async {
      await pumpLayer(
        tester,
        board: buildBoard(focusedPanelId: 'sticky-1', collapsed: true),
      );

      expect(find.byType(BoardPanelFloatingChrome), findsNothing);
      expect(find.byTooltip('Text size'), findsNothing);
    });
  });
}
