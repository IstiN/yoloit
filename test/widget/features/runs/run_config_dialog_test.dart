import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/ui/run_config_dialog.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  /// Pumps an app shell with an "Open" button that shows the dialog and
  /// forwards its result to [onResult], then opens the dialog.
  Future<void> openDialog(
    WidgetTester tester, {
    RunConfig? initial,
    required ValueChanged<RunConfig?> onResult,
  }) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      BlocProvider<WorkspaceCubit>(
        create: (_) => WorkspaceCubit(),
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        onResult(
                          await RunConfigDialog.show(context, initial: initial),
                        );
                      },
                      child: const Text('Open'),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  /// Opens the preset dropdown (currently showing [current]) and picks [next].
  Future<void> selectPreset(
    WidgetTester tester,
    String current,
    String next,
  ) async {
    await tester.tap(find.text(current));
    await tester.pumpAndSettle();
    await tester.tap(find.text(next).last);
    await tester.pumpAndSettle();
  }

  /// Scrolls a dialog button into view (the dialog body scrolls) and taps it.
  Future<void> tapDialogButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('macOS preset fills defaults and seeds flutter quick actions', (
    tester,
  ) async {
    RunConfig? result;
    await openDialog(tester, onResult: (r) => result = r);
    expect(find.text('New Run Configuration'), findsOneWidget);

    await selectPreset(tester, 'No preset', 'Flutter App — macOS');

    expect(find.text('Flutter Run'), findsOneWidget);
    expect(find.text('flutter run -d macos --debug'), findsOneWidget);
    expect(find.text('Hot Reload'), findsWidgets);
    expect(find.text('Hot Restart'), findsWidgets);

    await tapDialogButton(tester, 'Save');

    final config = result!;
    expect(config.name, 'Flutter Run');
    expect(config.command, 'flutter run -d macos --debug');
    expect(config.isFlutterRun, isTrue);
    expect(
      config.quickActions.map((a) => a.id),
      containsAll(['flutter_hot_reload', 'flutter_hot_restart']),
    );
    expect(config.quickActions.map((a) => a.command), containsAll(['r', 'R']));
  });

  testWidgets('web preset fills chrome command; No preset clears actions', (
    tester,
  ) async {
    await openDialog(tester, onResult: (_) {});

    await selectPreset(tester, 'No preset', 'Flutter App — Web');
    expect(find.text('Flutter Run (Web)'), findsOneWidget);
    expect(find.text('flutter run -d chrome --debug'), findsOneWidget);
    expect(find.text('Hot Reload'), findsWidgets);

    await selectPreset(tester, 'Flutter App — Web', 'No preset');
    expect(find.text('Hot Reload'), findsNothing);
    expect(find.text('Hot Restart'), findsNothing);
  });

  testWidgets('save returns the edited config and drops blank quick actions', (
    tester,
  ) async {
    const initial = RunConfig(
      id: 'cfg1',
      name: 'My App',
      command: 'make run',
      workingDir: '/tmp/proj',
      quickActions: [
        RunQuickAction(
          id: 'q1',
          label: 'Build',
          icon: '',
          command: 'b',
          appendNewline: true,
        ),
      ],
    );
    RunConfig? result;
    await openDialog(tester, initial: initial, onResult: (r) => result = r);
    expect(find.text('Edit Run Configuration'), findsOneWidget);

    // A blank draft is added but dropped on save (toAction returns null).
    await tapDialogButton(tester, 'Add quick action');
    await tapDialogButton(tester, 'Save');

    final config = result!;
    expect(config.id, 'cfg1');
    expect(config.name, 'My App');
    expect(config.command, 'make run');
    expect(config.workingDir, '/tmp/proj');
    expect(config.quickActions, hasLength(1));
    final action = config.quickActions.single;
    expect(action.id, 'q1');
    expect(action.icon, 'bolt'); // blank icon falls back to the default
    expect(action.command, 'b');
    expect(action.appendNewline, isTrue);
  });

  testWidgets('save with empty fields keeps the dialog open', (tester) async {
    var resultCalled = false;
    await openDialog(tester, onResult: (_) => resultCalled = true);

    await tapDialogButton(tester, 'Save');
    expect(find.text('New Run Configuration'), findsOneWidget);
    expect(resultCalled, isFalse);

    await tapDialogButton(tester, 'Cancel');
    expect(resultCalled, isTrue);
  });

  testWidgets('flutter initial config keeps reload action and adds restart', (
    tester,
  ) async {
    const initial = RunConfig(
      id: 'cfg2',
      name: 'Fl',
      command: 'flutter run -d macos',
      isFlutterRun: true,
      quickActions: [
        RunQuickAction(
          id: 'mine',
          label: 'Hot Reload',
          icon: 'bolt',
          command: 'r',
        ),
      ],
    );
    RunConfig? result;
    await openDialog(tester, initial: initial, onResult: (r) => result = r);

    // Preset detected from the initial config.
    expect(find.text('Flutter App — macOS'), findsOneWidget);
    // Existing reload action kept, restart seeded by _ensureFlutterQuickActions.
    expect(find.text('Hot Reload'), findsWidgets);
    expect(find.text('Hot Restart'), findsWidgets);

    await tapDialogButton(tester, 'Save');

    final config = result!;
    expect(config.isFlutterRun, isTrue);
    expect(
      config.quickActions.map((a) => a.id),
      containsAll(['mine', 'flutter_hot_restart']),
    );
  });
}
