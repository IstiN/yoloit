import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
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

    expect(find.byTooltip('Panel settings'), findsNWidgets(2));
    expect(find.byTooltip('Bring to front'), findsNWidgets(2));
    expect(find.byTooltip('Send to back'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Bring to front').first);
    await tester.pump();

    final updated = cubit.state.activeBoard!.panels.singleWhere(
      (panel) => panel.id == 'target',
    );
    expect(updated.zIndex, greaterThan(sibling.zIndex));
  });
}
