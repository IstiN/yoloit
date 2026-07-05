import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_event.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/yolo_assistant_plugin_base.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('standard panel chrome exposes settings and z-index controls', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const target = BoardPanelInstance(
      id: 'target',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Weather — Spitalfields',
      bounds: BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
      zIndex: 1,
      state: {'markdown': 'Weather panel'},
    );
    const sibling = BoardPanelInstance(
      id: 'sibling',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Sibling',
      bounds: BoardPanelBounds(x: 640, y: 74, width: 260, height: 180),
      zIndex: 4,
      state: {'markdown': 'Sibling panel'},
    );
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1),
      panels: [target, sibling],
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

    expect(find.text('Weather — Spitalfields'), findsOneWidget);
    expect(find.text('Sibling'), findsOneWidget);
    expect(find.text('Weather — Spitalfields'), findsOneWidget);
    expect(find.text('Sibling'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsNWidgets(2));

    await tester.tap(find.byTooltip('More actions').first);
    await tester.pump();

    expect(find.byTooltip('Bring to front'), findsOneWidget);
    expect(find.byTooltip('Send to back'), findsOneWidget);
    expect(find.byTooltip('Settings'), findsOneWidget);

    await tester.tap(find.byTooltip('Bring to front'));
    await tester.pump();

    final updated = cubit.state.activeBoard!.panels.singleWhere(
      (panel) => panel.id == 'target',
    );
    expect(updated.zIndex, greaterThan(sibling.zIndex));
  });

  testWidgets('markdown panel header exposes edit content action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const target = BoardPanelInstance(
      id: 'target',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Weather — Spitalfields',
      bounds: BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
      zIndex: 1,
      state: {'markdown': 'Weather panel'},
    );
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1),
      panels: [target],
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

    expect(find.byTooltip('Edit content'), findsOneWidget);

    await tester.tap(find.byTooltip('Edit content'));
    await tester.pumpAndSettle();

    expect(find.text('Edit markdown note'), findsOneWidget);
  });

  testWidgets('left toolbar opens board history and restores deleted panel', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    const target = BoardPanelInstance(
      id: 'target',
      type: MarkdownNotePlugin.kTypeId,
      title: 'Article draft',
      bounds: BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
      zIndex: 1,
      state: {'markdown': 'Long text'},
    );
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1),
    );
    cubit.emit(
      const BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    await historyStore.append(
      BoardHistoryEvent(
        opId: 'op-delete-target',
        boardId: 'board',
        type: 'delete',
        entityType: 'panel',
        entityId: 'target',
        actorId: 'tester',
        timestamp: DateTime.utc(2026, 5, 31, 12),
        revision: 1,
        before: target.toJson(),
      ),
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

    await tester.tap(find.byTooltip('Show board history'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Board history'), findsOneWidget);
    expect(find.textContaining('Deleted Article draft'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(
      cubit.state.activeBoard!.panels.any((panel) => panel.id == 'target'),
      isTrue,
    );
  });

  testWidgets('left toolbar exposes Miro basics category directly', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1),
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

    expect(find.byTooltip('Add panel'), findsNothing);

    await tester.tap(find.byTooltip('Miro basics'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Markdown Note'), findsOneWidget);
    expect(find.text('Sticky Note'), findsOneWidget);
    expect(find.text('Shape / Frame'), findsOneWidget);
    expect(find.text('Diagram'), findsNothing);

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('left toolbar category buttons open concrete panel types', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    const board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(scale: 1),
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

    expect(find.byTooltip('Add panel'), findsNothing);
    expect(find.byTooltip('Miro basics'), findsOneWidget);
    expect(find.byTooltip('AI and terminal'), findsOneWidget);
    expect(find.byTooltip('Files and web'), findsOneWidget);
    expect(find.byTooltip('Planning'), findsOneWidget);
    expect(find.byTooltip('Advanced'), findsOneWidget);

    await tester.tap(find.byTooltip('Files and web'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Markdown Note'), findsNothing);
    expect(find.text('File Tree'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('File Preview'), findsOneWidget);
    expect(find.text('Webpage'), findsOneWidget);
  });

  testWidgets(
    'focused panel shows YoLo badge and expands inline assistant overlay',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1200, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final cubit = BoardCubit();
      addTearDown(cubit.close);
      const target = BoardPanelInstance(
        id: 'target',
        type: MarkdownNotePlugin.kTypeId,
        title: 'Article draft',
        bounds: BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
        zIndex: 1,
        state: {'markdown': 'Long text'},
      );
      const board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1, focusedPanelId: 'target'),
        panels: [target],
      );
      cubit.emit(
        const BoardState(
          boards: [board],
          activeBoardId: 'board',
          isLoaded: true,
        ),
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

      expect(
        find.bySemanticsLabel('Ask YoLo about this panel'),
        findsOneWidget,
      );

      cubit.openYoloAssistant('target');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(cubit.state.yoloAssistantAnchorPanelId, 'target');
      final panels = cubit.state.activeBoard!.panels;
      expect(
        panels.where((p) => p.type == YoloAssistantPluginBase.kTypeId),
        isEmpty,
      );
      expect(find.text('YOLO'), findsWidgets);
      expect(find.byTooltip('Close YoLo assistant'), findsOneWidget);

      cubit.closeYoloAssistant();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump(const Duration(seconds: 13));

      expect(cubit.state.yoloAssistantAnchorPanelId, isNull);
    },
  );
}
