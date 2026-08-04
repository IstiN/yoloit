import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/runs/bloc/run_state.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_session.dart';

import 'run_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('console header actions', () {
    testWidgets('stop button stops a running session with quick actions', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Flutter App', flutter: true);
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      await pumpRunPanel(tester, cubit, RunPanelCallbacks());

      // Default flutter quick actions are shown for a running flutter session.
      expect(
        find.byIcon(Icons.local_fire_department_rounded),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.restart_alt_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.local_fire_department_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.triggered, ['s1_1:flutter_hot_reload']);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.stopped, ['s1_1']);
    });

    testWidgets('custom quick action button triggers cubit', (tester) async {
      const action = RunQuickAction(
        id: 'qa1',
        label: 'Build',
        icon: 'unknown_icon',
        command: 'make',
        appendNewline: true,
      );
      final config = runPanelConfig(
        'c1',
        name: 'Make App',
        quickActions: [action],
      );
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      await pumpRunPanel(tester, cubit, RunPanelCallbacks());

      // Unknown icon names fall back to the bolt icon.
      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
      await tester.tap(find.byIcon(Icons.bolt_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.triggered, ['s1_1:qa1']);
    });

    testWidgets('re-run button restarts a stopped session', (tester) async {
      final config = runPanelConfig('c1', name: 'Stopped App');
      final session = runPanelSession(
        's1_1',
        config,
        status: RunStatus.stopped,
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

      await tester.tap(find.byIcon(Icons.refresh_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.restarted, ['s1_1']);

      // Console header re-run icon also restarts.
      await tester.tap(find.byIcon(Icons.replay_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.restarted, ['s1_1', 's1_1']);
    });

    testWidgets('clear and scroll buttons act on the active session', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Noisy App');
      final session = runPanelSession(
        's1_1',
        config,
        output: List.generate(50, (i) => runPanelLine('line $i')),
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

      await tester.tap(find.byIcon(Icons.clear_all_rounded));
      await pumpRunPanelFrames(tester);
      expect(cubit.cleared, ['s1_1']);

      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_down_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.byIcon(Icons.keyboard_double_arrow_up_rounded));
      await pumpRunPanelFrames(tester);
    });

    testWidgets('detach button hides and detaches the session', (tester) async {
      final config = runPanelConfig('c1', name: 'Detach App');
      final session = runPanelSession('s1_1', config);
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

      await tester.tap(find.byIcon(Icons.link_off_rounded));
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s1_1:true']);
      expect(callbacks.attached, [null]);
    });

    testWidgets('detach-to-panel button pops the session out', (tester) async {
      final config = runPanelConfig('c1', name: 'Popout App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withDetachToPanel: true);

      await tester.tap(find.byIcon(Icons.open_in_new_rounded));
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s1_1:true']);
      expect(callbacks.detached.map((s) => s.id), ['s1_1']);
      expect(callbacks.attached, [null]);
    });
  });

  group('send to group', () {
    testWidgets('sends session to an existing group', (tester) async {
      final config = runPanelConfig('c1', name: 'Send App');
      final other = runPanelConfig('c2', name: 'Other App', group: 'g2');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config, other],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withSendToGroup: true);

      await tester.tap(find.byIcon(Icons.group_work_rounded));
      await pumpRunPanelFrames(tester);
      expect(find.text('Send to group'), findsOneWidget);

      await tester.tap(find.text('g2'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.sent, ['s1_1:g2:false']);
      expect(callbacks.visibility, ['s1_1:true']);
      expect(callbacks.attached, [null]);
    });

    testWidgets('creates a new group panel with a typed name', (tester) async {
      final config = runPanelConfig('c1', name: 'Send App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withSendToGroup: true);

      await tester.tap(find.byIcon(Icons.group_work_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Create new group panel'));
      await pumpRunPanelFrames(tester);

      expect(find.text('New group'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'backend');
      await tester.tap(find.text('Create'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.sent, ['s1_1:backend:true']);
    });

    testWidgets('cancel closes the dialog without sending', (tester) async {
      final config = runPanelConfig('c1', name: 'Send App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withSendToGroup: true);

      await tester.tap(find.byIcon(Icons.group_work_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Cancel'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.sent, isEmpty);
      expect(callbacks.visibility, isEmpty);
    });
  });

  group('run menu', () {
    testWidgets('detach from console menu item detaches the session', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final session = runPanelSession('s1_1', config);
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

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      // Optional menu items are hidden without their callbacks.
      expect(find.text('Detach to new panel'), findsNothing);
      expect(find.text('Send to group'), findsNothing);

      await tester.tap(find.text('Detach from console'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s1_1:true']);
      expect(callbacks.attached, [null]);
    });

    testWidgets('detach to new panel menu item pops out the session', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withDetachToPanel: true);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Detach to new panel'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.detached.map((s) => s.id), ['s1_1']);
      expect(callbacks.attached, [null]);
    });

    testWidgets('send to group menu item opens the group picker', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final other = runPanelConfig('c2', name: 'Other App', group: 'g2');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config, other],
          sessions: [session],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks, withSendToGroup: true);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Send to group'));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('g2'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.sent, ['s1_1:g2:false']);
    });

    testWidgets('attach latest session switches group and attaches', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final otherConfig = runPanelConfig('c2', name: 'Latest App', group: 'g2');
      final session = runPanelSession(
        's1_1',
        config,
        status: RunStatus.stopped,
      );
      final latest = runPanelSession('s2_2', otherConfig);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config, otherConfig],
          sessions: [session, latest],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Attach latest session'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s2_2:false']);
      expect(callbacks.groups, ['g2']);
      // The group switch is only signaled: the panel still shows g1, so the
      // freshly attached g2 session is auto-detached again.
      expect(callbacks.attached, ['s2_2', null]);
    });

    testWidgets('attach picker attaches the selected session', (tester) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final otherConfig = runPanelConfig('c2', name: 'Picked App', group: 'g2');
      final session = runPanelSession('s1_1', config);
      final other = runPanelSession('s2_2', otherConfig);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config, otherConfig],
          sessions: [session, other],
          activeSessionId: session.id,
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Attach…'));
      await pumpRunPanelFrames(tester);
      expect(find.text('Attach session'), findsOneWidget);

      await tester.tap(find.text('Picked App'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s2_2:false']);
      expect(callbacks.groups, ['g2']);
      // As above, the out-of-group session is auto-detached after attaching.
      expect(callbacks.attached, ['s2_2', null]);
    });

    testWidgets('attach picker cancel attaches nothing', (tester) async {
      final config = runPanelConfig('c1', name: 'Menu App');
      final session = runPanelSession('s1_1', config);
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

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Attach…'));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Cancel'));
      await pumpRunPanelFrames(tester);
      expect(callbacks.attached, isEmpty);
    });
  });

  group('session attach without active session', () {
    testWidgets('attach button picks a session from the dialog', (
      tester,
    ) async {
      final config = runPanelConfig('c1', name: 'Idle App');
      final session = runPanelSession('s1_1', config);
      final cubit = FakeRunCubit(
        RunState(
          configs: [config],
          sessions: [session],
          workspacePath: '/ws',
        ),
      );
      final callbacks = RunPanelCallbacks();
      await pumpRunPanel(tester, cubit, callbacks);

      await tester.tap(find.byIcon(Icons.link_rounded));
      await pumpRunPanelFrames(tester);
      await tester.tap(find.text('Idle App').last);
      await pumpRunPanelFrames(tester);
      expect(callbacks.visibility, ['s1_1:false']);
      expect(callbacks.attached, ['s1_1']);
    });
  });
}
