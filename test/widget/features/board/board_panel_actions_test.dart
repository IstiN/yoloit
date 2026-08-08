import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/board_panel_actions.dart';

class _Host extends StatelessWidget {
  const _Host({this.panel});

  final BoardPanelInstance? panel;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          TextButton(
            onPressed: () => BoardPanelActions.showAddNoteDialog(context),
            child: const Text('Add note'),
          ),
          TextButton(
            onPressed: BoardPanelActions.createEditCallback(
              context,
              panel ?? _unknownPanel,
            ),
            child: const Text('Edit note'),
          ),
        ],
      ),
    );
  }
}

const _unknownPanel = BoardPanelInstance(
  id: 'unknown-1',
  type: 'board.does.not.exist',
  title: 'Unknown',
  bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
);

const _markdownPanel = BoardPanelInstance(
  id: 'note-1',
  type: MarkdownNotePlugin.kTypeId,
  title: 'Old title',
  bounds: BoardPanelBounds(x: 10, y: 10, width: 320, height: 220),
  state: {'markdown': 'old body'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<BoardCubit> pumpHost(
    WidgetTester tester, {
    BoardPanelInstance? panel,
  }) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    final board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: const BoardViewport(scale: 1),
      panels: panel == null ? const [] : [panel],
    );
    cubit.emit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: _Host(panel: panel),
        ),
      ),
    );
    await tester.pump();
    return cubit;
  }

  Finder titleField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField && widget.decoration?.labelText == 'Title',
  );

  Finder markdownField() => find.byWidgetPredicate(
    (widget) =>
        widget is TextField &&
        widget.decoration?.hintText == 'Write markdown here...',
  );

  Future<void> openAddDialog(WidgetTester tester) async {
    await tester.tap(find.text('Add note'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Add markdown note'), findsOneWidget);
  }

  List<BoardPanelInstance> panels(BoardCubit cubit) =>
      cubit.state.activeBoard!.panels;

  group('add markdown note dialog', () {
    testWidgets('saves a new markdown panel', (tester) async {
      final cubit = await pumpHost(tester);
      await openAddDialog(tester);

      await tester.enterText(titleField(), 'Shopping list');
      await tester.enterText(markdownField(), '- milk\n- eggs');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(panels(cubit), hasLength(1));
      final created = panels(cubit).single;
      expect(created.type, MarkdownNotePlugin.kTypeId);
      expect(created.title, 'Shopping list');
      expect(created.state['markdown'], '- milk\n- eggs');
    });

    testWidgets('cancel leaves the board unchanged', (tester) async {
      final cubit = await pumpHost(tester);
      await openAddDialog(tester);

      await tester.enterText(titleField(), 'Discarded');
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(panels(cubit), isEmpty);
    });

    testWidgets('preview toggle and toolbar buttons transform the draft', (
      tester,
    ) async {
      final cubit = await pumpHost(tester);
      await openAddDialog(tester);

      await tester.enterText(markdownField(), 'hello');
      // Collapsed cursor at the end: the heading tool inserts a prefixed
      // placeholder line ('# item') at the cursor.
      await tester.tap(find.byTooltip('Heading'));
      await tester.pump();

      // Preview renders the raw draft as plain text.
      await tester.tap(find.text('Preview'));
      await tester.pump();
      expect(find.text('hello# item'), findsOneWidget);
      await tester.tap(find.text('Edit'));
      await tester.pump();
      expect(markdownField(), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(panels(cubit), hasLength(1));
      expect(panels(cubit).single.state['markdown'], 'hello# item');
    });

    testWidgets('color swatch applies the picked color to the new panel', (
      tester,
    ) async {
      final cubit = await pumpHost(tester);
      await openAddDialog(tester);

      // The 28x28 color swatch inside the note dialog.
      final swatch = find.byWidgetPredicate(
        (widget) =>
            widget is Container && widget.constraints?.maxWidth == 28,
      );
      await tester.tap(swatch);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Panel color'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.enterText(titleField(), 'Colored');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(panels(cubit), hasLength(1));
      expect(panels(cubit).single.color, isNotNull);
    });
  });

  group('edit markdown note dialog', () {
    testWidgets('updates the existing panel', (tester) async {
      final cubit = await pumpHost(tester, panel: _markdownPanel);
      await tester.tap(find.text('Edit note'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Edit markdown note'), findsOneWidget);
      expect(
        tester.widget<TextField>(markdownField()).controller?.text,
        'old body',
      );

      await tester.enterText(titleField(), 'New title');
      await tester.enterText(markdownField(), 'new body');
      await tester.tap(find.text('Save'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final updated = panels(cubit).singleWhere((p) => p.id == 'note-1');
      expect(updated.title, 'New title');
      expect(updated.state['markdown'], 'new body');
    });

    testWidgets('returns null for panel types without an editor', (
      tester,
    ) async {
      await pumpHost(tester);
      // The host wires the Edit button through createEditCallback with an
      // unknown panel type: the callback is null, so the button is disabled.
      final button = tester.widget<TextButton>(
        find.widgetWithText(TextButton, 'Edit note'),
      );
      expect(button.onPressed, isNull);
    });
  });
}
