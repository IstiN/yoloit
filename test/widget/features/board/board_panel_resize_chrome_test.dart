import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';
import 'package:yoloit/features/board/tools/board_tool.dart';
import 'package:yoloit/features/board/ui/board_panel_layer.dart';
import 'package:yoloit/features/board/ui/board_panel_resize_chrome.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('resize chrome stays above overlapping panels', (tester) async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);

    const target = BoardPanelInstance(
      id: 'target',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Resize me',
      bounds: BoardPanelBounds(x: 80, y: 80, width: 320, height: 220),
      zIndex: 1,
      state: {'markdown': 'Target'},
    );
    const overlap = BoardPanelInstance(
      id: 'overlap',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Overlap',
      bounds: BoardPanelBounds(x: 340, y: 220, width: 200, height: 160),
      zIndex: 9,
      state: {'markdown': 'Overlap'},
    );
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1, focusedPanelId: 'target'),
      panels: [target, overlap],
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    var resizeUpdates = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 900,
              height: 700,
              child: BoardPanelLayer(
                board: board,
                canvasOrigin: Offset.zero,
                isCapturingScreenshot: false,
                selectedPanelIds: const {'target'},
                activeTool: BoardToolId.select,
                connectSourceId: null,
                onMovePanel: (context, panelId, details) {},
                onResizePanel: (_, panel, update) {
                  resizeUpdates++;
                },
                onDragStart: (panelId, details) {},
                onDragEnd: () {},
                onConnectTap: (context, board, panelId) {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(BoardPanelResizeChrome), findsOneWidget);

    final handle = find.byTooltip('Resize from bottom right');
    await tester.drag(handle, const Offset(40, 24));
    await tester.pump();

    expect(cubit.state.activeBoard!.viewport.focusedPanelId, 'target');
    expect(resizeUpdates, greaterThan(0));
  });

  testWidgets('markdown panel keeps focus when switching from sticky note', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = BoardCubit();
    addTearDown(cubit.close);

    const sticky = BoardPanelInstance(
      id: 'sticky',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky',
      bounds: BoardPanelBounds(x: 520, y: 120, width: 180, height: 140),
      zIndex: 2,
      state: {'text': 'High impact, low effort'},
    );
    const markdown = BoardPanelInstance(
      id: 'markdown',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Initiatives Prioritization',
      bounds: BoardPanelBounds(x: 80, y: 80, width: 360, height: 260),
      zIndex: 1,
      state: {'markdown': '## Initiatives'},
    );
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1, focusedPanelId: 'sticky'),
      panels: [markdown, sticky],
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(value: cubit, child: const BoardView()),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 450));

    expect(cubit.state.activeBoard!.viewport.focusedPanelId, 'sticky');
    expect(find.byType(BoardPanelResizeChrome), findsOneWidget);

    await tester.tap(find.text('Initiatives Prioritization'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(cubit.state.activeBoard!.viewport.focusedPanelId, 'markdown');
    expect(find.byType(BoardPanelResizeChrome), findsOneWidget);
    expect(find.byTooltip('Resize from bottom right'), findsOneWidget);

    final beforeResize =
        cubit.state.activeBoard!.panels
            .where((panel) => panel.id == 'markdown')
            .single
            .bounds;

    await tester.drag(
      find.byKey(const ValueKey('panel-resize-handle-bottomRight')),
      const Offset(48, 32),
    );
    await tester.pump();

    final afterResize =
        cubit.state.activeBoard!.panels
            .where((panel) => panel.id == 'markdown')
            .single
            .bounds;
    expect(afterResize.width, greaterThan(beforeResize.width));
    expect(afterResize.height, greaterThan(beforeResize.height));
  });
}
