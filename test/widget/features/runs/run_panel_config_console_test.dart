import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

import 'run_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('session tabs', () {
    testWidgets('tapping a tab attaches it, close removes it', (tester) async {
      final config1 = runPanelConfig('c1', name: 'Tab One');
      final config2 = runPanelConfig('c2', name: 'Tab Two');
      final s1 = runPanelSession('s1_1', config1);
      final s2 = runPanelSession('s2_2', config2);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config1, config2],
          sessions: [s1, s2],
          activeSessionId: s1.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      await tester.tap(find.text('Tab Two').last);
      await pumpRunPanelFrames(tester);
      expect(callbacks.attached, ['s2_2']);

      await tester.tap(find.byIcon(Icons.close).first);
      await pumpRunPanelFrames(tester);
      expect(cubit.removed, ['s1_1']);
    });

    testWidgets('hidden tabs show the active session name instead', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Solo App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      await pumpRunPanel(
        tester,
        cubit,
        RunPanelCallbacks(),
        showSessionTabs: false,
      );
      expect(find.text('Solo App'), findsWidgets);
    });
  });

  group('config list', () {
    testWidgets('run button hot-reloads, restarts or starts configs', (
      tester,
    ) async {
      final flutterConfig = runPanelConfig(
        'c1',
        name: 'Running App',
        flutter: true,
      );
      final stoppedConfig = runPanelConfig('c2', name: 'Stopped App');
      final freshConfig = runPanelConfig('c3', name: 'Fresh App');
      final running = runPanelSession('s1_1', flutterConfig);
      final stoppedSession = runPanelSession(
        's2_2',
        stoppedConfig,
        status: RunStatus.stopped,
      );
      final cubit = FakeRunCubit(
        RunState(
          configs: [flutterConfig, stoppedConfig, freshConfig],
          sessions: [running, stoppedSession],
          activeSessionId: running.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      // Running flutter config: hot reload. The session is already attached,
      // so no attach callback fires.
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).first);
      await pumpRunPanelFrames(tester);
      expect(cubit.hotReloads, ['s1_1']);
      expect(callbacks.attached, isEmpty);

      // Stopped config: restart + attach (requires hover to enable).
      await hoverRunPanel(tester, find.text('Stopped App').first);
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).at(1));
      await pumpRunPanelFrames(tester);
      expect(cubit.restarted, ['s2_2']);
      expect(callbacks.attached.last, 's2_2');

      // Fresh config: start a new run.
      await hoverRunPanel(tester, find.text('Fresh App'));
      await tester.tap(find.byIcon(Icons.play_arrow_rounded).at(2));
      await pumpRunPanelFrames(tester);
      expect(cubit.started.map((c) => c.id), ['c3']);
    });

    testWidgets('options menu edits and deletes a config', (tester) async {
      final config = runPanelConfig('c1', name: 'Editable App');
      final cubit = FakeRunCubit(
        RunState(configs: [config], workspacePath: '/ws'),
      );
      await pumpRunPanel(tester, cubit, RunPanelCallbacks());

      await hoverRunPanel(tester, find.text('Editable App').first);
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Delete'));
      await pumpRunPanelFrames(tester);
      expect(cubit.removedConfigIds, ['c1']);

      await hoverRunPanel(tester, find.text('Editable App').first);
      await tester.tap(find.byIcon(Icons.more_vert));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Edit'));
      await pumpRunPanelFrames(tester);
      // RunConfigDialog is open; cancelling leaves configs untouched.
      await tester.tap(find.text('Cancel'));
      await pumpRunPanelFrames(tester);
      expect(cubit.updatedConfigs, isEmpty);
    });

    testWidgets('add configuration tile opens the dialog', (tester) async {
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      await pumpRunPanel(tester, cubit, RunPanelCallbacks());

      await tester.tap(find.text('Add Configuration'));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Cancel'));
      await pumpRunPanelFrames(tester);
      expect(cubit.addedConfigs, isEmpty);
    });

    testWidgets('group rename applies, ignores blank and cancels', (
      tester,
    ) async {
      final cubit = FakeRunCubit(const RunState(workspacePath: '/ws'));
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      // Blank input is ignored.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpRunPanelFrames(tester);
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(find.text('Apply'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.groups, isEmpty);

      // Cancel leaves the group unchanged.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Cancel'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.groups, isEmpty);

      // A real name is applied.
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await pumpRunPanelFrames(tester);
      await tester.enterText(find.byType(TextField), 'backend');
      await tester.tap(find.text('Apply'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.groups, ['backend']);
    });

    testWidgets('session groups attach and delete sessions', (tester) async {
      final config = runPanelConfig('c1', name: 'Grouped App');
      final s1 = runPanelSession('s1_1', config, status: RunStatus.failed);
      final s2 = runPanelSession('s2_2', config, status: RunStatus.stopped);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [s1, s2],
          activeSessionId: s1.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(
        tester,
        cubit,
        callbacks,
        showSessionTabs: false,
      );

      // Session rows show the id suffix and the start time.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('10:30'), findsNWidgets(2));

      await tester.tap(find.text('2'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.attached, ['s2_2']);

      // Sessions render newest first, so the first close icon is s2_2's.
      await tester.tap(find.byIcon(Icons.close).first);
      await pumpRunPanelFrames(tester);
      expect(cubit.removed, ['s2_2']);
    });
  });

  group('console output', () {
    testWidgets('renders colored lines and copies all output', (tester) async {
      final config = runPanelConfig('c1', name: 'Log App');
      final session = runPanelSession(
        's1_1',
        config,
        output: [
          runPanelLine('\n[Process exited with code 0]'),
          runPanelLine('Reloaded 5 libraries'),
          runPanelLine('boom', isError: true),
          runPanelLine('compilation error here'),
          runPanelLine('plain line'),
          runPanelLine('\x1B[31mansi text\x1B[0m'),
        ],
      );
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      await pumpRunPanel(tester, cubit, RunPanelCallbacks());

      expect(find.text('ansi text'), findsOneWidget);
      expect(find.text('plain line'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.copy_outlined));
      await pumpRunPanelFrames(tester);
      expect(find.text('Output copied to clipboard'), findsOneWidget);
      // Let the snackbar timer drain before the test ends.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    });

    testWidgets('empty console offers quick-run buttons', (tester) async {
      final config = runPanelConfig('c1', name: 'Quick App');
      final cubit = FakeRunCubit(
        RunState(configs: [config], workspacePath: '/ws'),
      );
      await pumpRunPanel(
        tester,
        cubit,
        RunPanelCallbacks(),
        showConfigList: false,
      );

      expect(
        find.text('Select a configuration from the left panel to run it'),
        findsOneWidget,
      );
      await tester.tap(find.text('Quick App'));
      await pumpRunPanelFrames(tester);
      expect(cubit.started.map((c) => c.id), ['c1']);
    });

    testWidgets('without a workspace it prompts and triggers a load', (
      tester,
    ) async {
      final cubit = FakeRunCubit(const RunState());
      await pumpRunPanel(
        tester,
        cubit,
        RunPanelCallbacks(),
        showConfigList: false,
      );

      expect(find.text('Open a workspace to get started'), findsOneWidget);
      expect(cubit.loadCalls, 1);
    });
  });

  group('state updates', () {
    testWidgets('output growth scrolls and session loss auto-detaches', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Live App');
      final session = runPanelSession(
        's1_1',
        config,
        output: [runPanelLine('one')],
      );
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      cubit.emit(
        cubit.state.copyWith(
          sessions: [
            runPanelSession(
              's1_1',
              config,
              output: [runPanelLine('one'), runPanelLine('two')],
            ),
          ],
        ),
      );
      await pumpRunPanelFrames(tester);
      expect(find.text('two'), findsOneWidget);

      // Session disappears from the board: the panel auto-detaches.
      cubit.emit(cubit.state.copyWith(sessions: const []));
      await pumpRunPanelFrames(tester);
      expect(callbacks.attached, [null]);
    });
  });
}
