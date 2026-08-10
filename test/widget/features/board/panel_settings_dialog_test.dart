import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/panel_settings_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panel = BoardPanelInstance(
    id: 'p1',
    type: MarkdownNotePlugin.kTypeId,
    title: 'Note',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
    state: {'markdown': 'hi'},
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BoardCubit> pumpSettings(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board', panels: [panel])],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: PanelSettingsDialog(
              panel: panel,
              plugin: const MarkdownNotePlugin(),
              onEditColor: () {},
              onBringToFront: () {},
              onSendToBack: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return cubit;
  }

  Future<void> openNewGroupDialog(WidgetTester tester) async {
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.text('Group name'), findsOneWidget);
  }

  testWidgets('creating a new group stores it via the board cubit', (
    tester,
  ) async {
    final cubit = await pumpSettings(tester);

    await openNewGroupDialog(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Group name'),
      'Sprint 1',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    final groups = cubit.state.activeBoard!.groups;
    expect(groups, hasLength(1));
    expect(groups.single.name, 'Sprint 1');
    expect(groups.single.panelIds, ['p1']);
  });

  testWidgets('cancelling the name dialog creates no group', (tester) async {
    final cubit = await pumpSettings(tester);

    await openNewGroupDialog(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cubit.state.activeBoard!.groups, isEmpty);
  });

  testWidgets('an empty group name creates no group', (tester) async {
    final cubit = await pumpSettings(tester);

    await openNewGroupDialog(tester);
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(cubit.state.activeBoard!.groups, isEmpty);
  });
}
