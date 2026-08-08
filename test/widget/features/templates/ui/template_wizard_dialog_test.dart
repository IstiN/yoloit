import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/templates/bloc/templates_cubit.dart';
import 'package:yoloit/features/templates/model/template_models.dart';
import 'package:yoloit/features/templates/ui/template_wizard_dialog.dart';

import '../../../../unit/helpers/mock_board_cubit.dart';

/// A [TemplatesCubit] pre-seeded with templates so the wizard never triggers
/// the real disk/network load path.
class _TestTemplatesCubit extends TemplatesCubit {
  _TestTemplatesCubit({List<BoardTemplate> templates = const []}) {
    emit(TemplatesState(templates: templates));
  }

  void seed(TemplatesState value) => emit(value);
}

/// A [MockBoardCubit] with the bloc plumbing stubbed so it can sit inside a
/// [BlocProvider] (provider subscribes to `stream` the first time the cubit
/// is read from the widget tree).
MockBoardCubit createStubbedBoardCubit() {
  final cubit = MockBoardCubit();
  when(() => cubit.stream).thenAnswer((_) => const Stream<BoardState>.empty());
  when(() => cubit.state).thenReturn(const BoardState());
  return cubit;
}

void main() {
  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  BoardTemplate tripTemplate() => const BoardTemplate(
    id: 'trip',
    name: 'Trip Planner',
    icon: 'trip',
    description: 'Plan your next adventure',
    parameters: [
      TemplateParameter(
        name: 'destination',
        type: TemplateParameterType.string,
        label: 'Destination',
        defaultValue: 'Paris',
      ),
      TemplateParameter(
        name: 'includeBudget',
        type: TemplateParameterType.boolean,
        label: 'Include budget',
        defaultValue: true,
      ),
    ],
    sourceId: 'test',
  );

  BoardTemplate kanbanTemplate() => const BoardTemplate(
    id: 'kanban',
    name: 'Kanban Board',
    icon: 'kanban',
    operations: [
      TemplateOperation(
        payload: {
          'op': 'panel.create',
          'type': 'board.kanban',
          'title': 'Kanban',
        },
      ),
    ],
    sourceId: 'test',
  );

  BoardTemplate requiredParamTemplate() => const BoardTemplate(
    id: 'project',
    name: 'Project Board',
    icon: 'roadmap',
    description: 'Project with a required parameter',
    parameters: [
      TemplateParameter(
        name: 'projectName',
        type: TemplateParameterType.string,
        label: 'Project name',
        required: true,
      ),
    ],
    sourceId: 'test',
  );

  void useLargeSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Future<void> openWizard(
    WidgetTester tester,
    _TestTemplatesCubit cubit, {
    MockBoardCubit? boardCubit,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      BlocProvider<BoardCubit>.value(
        // The dialog route must see the BoardCubit, so it lives above the
        // MaterialApp navigator (mirrors the app-level provider in lib/app).
        value: boardCubit ?? createStubbedBoardCubit(),
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Builder(
            builder:
                (context) => Scaffold(
                  body: Center(
                    child: FilledButton(
                      onPressed:
                          () => showDialog<void>(
                            context: context,
                            builder:
                                (_) => BlocProvider<TemplatesCubit>.value(
                                  value: cubit,
                                  child: const TemplateWizardDialog(),
                                ),
                          ),
                      child: const Text('Open wizard'),
                    ),
                  ),
                ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open wizard'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
  }

  Future<void> goToConfigure(
    WidgetTester tester,
    String templateName,
  ) async {
    await tester.tap(find.widgetWithText(InkWell, templateName));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  group('selection step', () {
    testWidgets('shows empty state when there are no templates', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(tester, _TestTemplatesCubit());

      expect(find.text('Choose a template'), findsOneWidget);
      expect(
        find.text('No templates found.\nAdd a source in Settings → Templates.'),
        findsOneWidget,
      );
      expect(find.text('Next'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('shows loading indicator while templates load', (tester) async {
      useLargeSurface(tester);
      final cubit = _TestTemplatesCubit();
      await openWizard(tester, cubit, settle: false);

      cubit.seed(const TemplatesState(isLoading: true));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsWidgets);
    });

    testWidgets('lists templates and prompts for a preview before selection', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate(), kanbanTemplate()]),
      );

      expect(find.text('Trip Planner'), findsOneWidget);
      expect(find.text('Kanban Board'), findsOneWidget);
      expect(
        find.text('Select a template to see a preview'),
        findsOneWidget,
      );
    });

    testWidgets('Next without a selection shows a snackbar', (tester) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
      );

      await tester.tap(find.text('Next'));
      await tester.pump();

      expect(find.text('Select a template'), findsOneWidget);
      // Still on the selection step.
      expect(find.text('Choose a template'), findsOneWidget);
    });

    testWidgets('selecting a template shows its details in the preview card', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate(), kanbanTemplate()]),
      );

      await tester.tap(find.widgetWithText(InkWell, 'Trip Planner'));
      await tester.pumpAndSettle();

      // Selected tile is marked and the preview card describes the template.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(find.text('Plan your next adventure'), findsWidgets);
      expect(find.text('Parameters'), findsOneWidget);
      expect(find.text('Destination'), findsOneWidget);
      expect(find.text('Include budget'), findsOneWidget);
      // The template creates no panels.
      expect(find.text('No panels'), findsOneWidget);
    });

    testWidgets('search filters by name and description and can be cleared', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate(), kanbanTemplate()]),
      );

      // Matches only the Trip Planner description.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search templates...'),
        'adventure',
      );
      await tester.pump();
      expect(find.text('Trip Planner'), findsOneWidget);
      expect(find.text('Kanban Board'), findsNothing);

      // No match.
      await tester.enterText(
        find.widgetWithText(TextField, 'Search templates...'),
        'zzz',
      );
      await tester.pump();
      expect(find.text('No templates match "zzz"'), findsOneWidget);

      // Clear restores the full list.
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pump();
      expect(find.text('Trip Planner'), findsOneWidget);
      expect(find.text('Kanban Board'), findsOneWidget);
    });

    testWidgets('shows a snackbar when the cubit reports an error', (
      tester,
    ) async {
      useLargeSurface(tester);
      final cubit = _TestTemplatesCubit(templates: [tripTemplate()]);
      await openWizard(tester, cubit);

      cubit.seed(
        TemplatesState(templates: [tripTemplate()], error: 'sync failed'),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('sync failed'), findsOneWidget);
    });

    testWidgets('Cancel closes the dialog', (tester) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(TemplateWizardDialog), findsNothing);
    });

    testWidgets('close icon closes the dialog', (tester) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
      );

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();

      expect(find.byType(TemplateWizardDialog), findsNothing);
    });
  });

  group('configure step', () {
    testWidgets('Next opens the form prefilled with template defaults', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
      );

      await goToConfigure(tester, 'Trip Planner');

      // Header switches to the template name, primary action becomes Create.
      expect(find.text('Create'), findsOneWidget);
      expect(find.text('Back'), findsOneWidget);
      // Board name is prefilled from the template name.
      final nameField = tester.widget<TextFormField>(
        find.widgetWithText(TextFormField, 'Board name'),
      );
      expect(nameField.controller?.text, 'Trip Planner');
      // Parameter default values are applied.
      expect(find.text('Destination'), findsOneWidget);
      expect(find.text('Paris'), findsOneWidget);
      expect(find.text('Include budget'), findsOneWidget);
    });

    testWidgets('Back returns to the selection step', (tester) async {
      useLargeSurface(tester);
      final cubit = _TestTemplatesCubit(templates: [tripTemplate()]);
      await openWizard(tester, cubit);

      await goToConfigure(tester, 'Trip Planner');
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      expect(find.text('Choose a template'), findsOneWidget);
      expect(find.text('Create'), findsNothing);
    });

    testWidgets('toggling a boolean parameter updates the wizard values', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
      );

      await goToConfigure(tester, 'Trip Planner');
      expect(find.text('Yes'), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pump();

      expect(find.text('No'), findsOneWidget);
    });

    testWidgets('Create with an empty board name shows a validation error', (
      tester,
    ) async {
      useLargeSurface(tester);
      final boardCubit = createStubbedBoardCubit();
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
        boardCubit: boardCubit,
      );

      await goToConfigure(tester, 'Trip Planner');
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Board name'),
        ' ',
      );
      await tester.tap(find.text('Create'));
      await tester.pump();

      expect(find.text('Board name is required'), findsOneWidget);
      verifyNever(
        () => boardCubit.createBoardFromOperations(
          name: any(named: 'name'),
          operations: any(named: 'operations'),
        ),
      );
    });

    testWidgets('Create with a missing required parameter shows its error', (
      tester,
    ) async {
      useLargeSurface(tester);
      final boardCubit = createStubbedBoardCubit();
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [requiredParamTemplate()]),
        boardCubit: boardCubit,
      );

      await goToConfigure(tester, 'Project Board');
      await tester.tap(find.text('Create'));
      await tester.pump();

      expect(find.text('Required'), findsOneWidget);
      verifyNever(
        () => boardCubit.createBoardFromOperations(
          name: any(named: 'name'),
          operations: any(named: 'operations'),
        ),
      );
    });

    testWidgets('Create builds the board and closes the dialog on success', (
      tester,
    ) async {
      useLargeSurface(tester);
      final boardCubit = createStubbedBoardCubit();
      when(
        () => boardCubit.createBoardFromOperations(
          name: any(named: 'name'),
          operations: any(named: 'operations'),
        ),
      ).thenAnswer(
        (_) async => const BoardDocument(id: 'board-1', name: 'Trip Planner'),
      );
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
        boardCubit: boardCubit,
      );

      await goToConfigure(tester, 'Trip Planner');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      verify(
        () => boardCubit.createBoardFromOperations(
          name: 'Trip Planner',
          operations: any(named: 'operations'),
        ),
      ).called(1);
      expect(find.byType(TemplateWizardDialog), findsNothing);
    });

    testWidgets('Create shows a snackbar when the board cannot be created', (
      tester,
    ) async {
      useLargeSurface(tester);
      final boardCubit = createStubbedBoardCubit();
      when(
        () => boardCubit.createBoardFromOperations(
          name: any(named: 'name'),
          operations: any(named: 'operations'),
        ),
      ).thenAnswer((_) async => null);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
        boardCubit: boardCubit,
      );

      await goToConfigure(tester, 'Trip Planner');
      await tester.tap(find.text('Create'));
      await tester.pump();

      expect(find.text('Could not create board'), findsOneWidget);
      // The wizard stays open so the user can retry.
      expect(find.byType(TemplateWizardDialog), findsOneWidget);
    });

    testWidgets('Create shows a snackbar when board creation throws', (
      tester,
    ) async {
      useLargeSurface(tester);
      final boardCubit = createStubbedBoardCubit();
      when(
        () => boardCubit.createBoardFromOperations(
          name: any(named: 'name'),
          operations: any(named: 'operations'),
        ),
      ).thenThrow(Exception('disk full'));
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [tripTemplate()]),
        boardCubit: boardCubit,
      );

      await goToConfigure(tester, 'Trip Planner');
      await tester.tap(find.text('Create'));
      await tester.pump();

      expect(
        find.text('Failed to create board: Exception: disk full'),
        findsOneWidget,
      );
      expect(find.byType(TemplateWizardDialog), findsOneWidget);
    });
  });

  group('preview card', () {
    testWidgets('shows panel chips for a template with panel operations', (
      tester,
    ) async {
      useLargeSurface(tester);
      await openWizard(
        tester,
        _TestTemplatesCubit(templates: [kanbanTemplate()]),
      );

      // Selecting starts the offscreen preview render; the panel chips render
      // immediately regardless of the pending image future.
      await tester.tap(find.widgetWithText(InkWell, 'Kanban Board'));
      await tester.pump();

      expect(find.text('Panels'), findsOneWidget);
      expect(find.text('1× kanban'), findsOneWidget);
      // The template declares no parameters.
      expect(find.text('Parameters'), findsOneWidget);
      expect(find.text('None'), findsOneWidget);

      // The offscreen render loop runs on real 50ms timers and, once it has
      // seen 4 consecutive idle turns, parks on the engine's `toImage` future.
      // Close the dialog (cancelling the render token) and let the loop
      // observe the cancellation in real async before it reaches `toImage`,
      // so it unwinds and restores ErrorWidget.builder before the test ends.
      await tester.runAsync(() async {
        await tester.tap(find.text('Cancel'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });

      expect(find.byType(TemplateWizardDialog), findsNothing);
    });
  });

  group('templateIcon', () {
    test('maps known icon names and falls back to the dashboard icon', () {
      const template = BoardTemplate(id: 't', name: 'T', sourceId: 'test');
      final cases = <String, IconData>{
        'flutter': Icons.flutter_dash,
        'home': Icons.home_outlined,
        'note': Icons.notes_outlined,
        'kanban': Icons.view_kanban_outlined,
        'trip': Icons.flight_takeoff_outlined,
        'habit': Icons.track_changes_outlined,
        'weekly': Icons.calendar_view_week_outlined,
        'lightbulb': Icons.lightbulb_outline,
        'roadmap': Icons.map_outlined,
        'story': Icons.account_tree_outlined,
        'retrospective': Icons.psychology_outlined,
        'journey': Icons.directions_outlined,
        'matrix': Icons.grid_on_outlined,
        'sprint': Icons.run_circle_outlined,
        'unknown': Icons.dashboard_outlined,
      };
      for (final entry in cases.entries) {
        expect(
          templateIcon(template.copyWith(icon: entry.key)),
          entry.value,
          reason: 'icon "${entry.key}"',
        );
      }
      expect(templateIcon(template), Icons.dashboard_outlined);
    });
  });
}
