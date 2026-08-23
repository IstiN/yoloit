import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

import 'board_terminal_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
    CanvasInteractionLock.instance.resetForTesting();
  });

  group('setup view', () {
    testWidgets('unconfigured panel shows create terminal form', (
      tester,
    ) async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(tester, panel: terminalPanel(), cubit: cubit);

      expect(find.text('Create terminal'), findsOneWidget);
      expect(find.text('Working Directory'), findsOneWidget);
      expect(find.text('Session Name'), findsOneWidget);
      expect(find.text('Select folder…'), findsOneWidget);
      expect(find.text('No groups selected'), findsOneWidget);

      final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start Terminal'),
      );
      expect(button.onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'my session');
      await tester.pump();
      // Still disabled: the working directory is empty.
      final afterInput = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start Terminal'),
      );
      expect(afterInput.onPressed, isNull);
    });

    testWidgets('config with empty working dir also shows setup view', (
      tester,
    ) async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(sessionName: 'named'),
        cubit: cubit,
      );

      expect(find.text('Create terminal'), findsOneWidget);
    });
  });

  group('connected view', () {
    testWidgets('shows info bar with shortened path and action icons', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/Users/test/projects/demo',
        ),
        cubit: cubit,
      );

      expect(find.text('.../projects/demo'), findsOneWidget);
      expect(find.byType(TerminalWidget), findsOneWidget);
      expect(find.byIcon(Icons.history), findsOneWidget);
      expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.open_in_full_rounded), findsOneWidget);
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);

      // Scroll actions are wired to the terminal widget state.
      await tester.tap(find.byIcon(Icons.keyboard_arrow_up));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.keyboard_arrow_down));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('short working dir is shown unmodified', (tester) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      expect(find.text('/tmp/demo'), findsOneWidget);
    });

    testWidgets('config change via didUpdateWidget keeps the session', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);

      final panelV1 = terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpTerminalPanel(tester, panel: panelV1, cubit: cubit);
      expect(find.text('/tmp/demo'), findsOneWidget);

      // Same session id, different name: didUpdateWidget re-reads the config
      // and resolves the already-live session again.
      final panelV2 = terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'renamed',
        workingDir: '/tmp/demo',
      );
      await tester.pumpWidget(buildTerminalPanelApp(panel: panelV2, cubit: cubit));
      await tester.pump();
      expect(find.byType(TerminalWidget), findsOneWidget);

      // Swapping the session object under the same id notifies the manager
      // listener and re-attaches the info bar terminal listener.
      manager.setSessionForTesting(
        'sess-1',
        liveTerminalSession('sess-1', name: 'demo2'),
      );
      await tester.pump();
      expect(find.byType(TerminalWidget), findsOneWidget);
    });

    testWidgets('TUI badge reflects alt-buffer changes', (tester) async {
      final manager = BoardTerminalSessionManager.instance;
      final session = liveTerminalSession('sess-1');
      manager.setSessionForTesting('sess-1', session);
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      expect(find.text('TUI'), findsNothing);

      session.terminal.write('\x1B[?1049h');
      await tester.pump();
      expect(find.text('TUI'), findsOneWidget);

      session.terminal.write('\x1B[?1049l');
      await tester.pump();
      expect(find.text('TUI'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('env key icon opens the env group picker dialog', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      await tester.tap(find.byIcon(Icons.key_outlined));
      await tester.pump();
      await tester.pump();
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Cancel'), findsNothing);
    });
  });

  group('kill and restart', () {
    testWidgets('kill shows disconnected view and restart reattaches', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      final session = liveTerminalSession('sess-1');
      manager.setSessionForTesting('sess-1', session);
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final panel = terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpTerminalPanel(tester, panel: panel, cubit: cubit, withBoard: true);
      expect(find.byType(TerminalWidget), findsOneWidget);

      // Kill the session: the manager notifies and the panel switches to the
      // disconnected view.
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
      await tester.pump();
      expect(find.text('demo ended'), findsOneWidget);
      expect(find.text('/tmp/demo'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Restart'), findsOneWidget);

      // Silently re-register the session (no manager notification) so the
      // restart path finds it already live instead of spawning a process.
      final controller = StreamController<String>();
      addTearDown(controller.close);
      manager.attachProcessForTesting(
        TerminalProcess(
          output: controller.stream,
          exitCode: Completer<int>().future,
        ),
        session,
      );

      await tester.tap(find.text('Restart'));
      await tester.pump();
      await tester.pump();
      expect(find.text('demo ended'), findsNothing);
      expect(find.byType(TerminalWidget), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('history button on disconnected view opens history dialog', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );
      await tester.tap(find.byIcon(Icons.stop_circle_outlined));
      await tester.pump();
      await tester.pump();
      expect(find.text('demo ended'), findsOneWidget);

      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsOneWidget);
      // Killing the session recorded it in the history store.
      expect(find.text('demo'), findsOneWidget);
      expect(find.text('saved • /tmp/demo'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsNothing);
    });
  });

  group('history dialog', () {
    testWidgets('shows empty state when no sessions were recorded', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      await tester.tap(find.byIcon(Icons.history));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsOneWidget);
      expect(find.text('No terminal sessions yet.'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsNothing);
    });

    void seedHistory() {
      SharedPreferences.setMockInitialValues({
        'board_terminal_session_history': jsonEncode([
          {
            'id': 'sess-1',
            'sessionName': 'demo',
            'workingDir': '/tmp/demo',
            'envGroupIds': <String>[],
            'createdAt': '2026-01-01T10:00:00.000',
            'lastActiveAt': '2026-01-02T10:00:00.000',
          },
          {
            'id': 'old-1',
            'sessionName': 'old session',
            'workingDir': '/var/old',
            'envGroupIds': <String>[],
            'createdAt': '2026-01-01T09:00:00.000',
          },
        ]),
      });
    }

    Future<void> openHistoryDialog(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.history));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('lists live and saved entries with actions', (tester) async {
      seedHistory();
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      await openHistoryDialog(tester);
      expect(find.text('Terminal history'), findsOneWidget);
      expect(find.text('demo'), findsOneWidget);
      expect(find.text('old session'), findsOneWidget);
      expect(find.text('live • /tmp/demo'), findsOneWidget);
      expect(find.text('saved • /var/old'), findsOneWidget);

      // Delete the saved (non-live) entry.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      await tester.pump();
      expect(find.text('old session'), findsNothing);

      // Kill the live entry from the dialog.
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.byIcon(Icons.stop_circle_outlined),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('saved • /tmp/demo'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsNothing);
    });

    testWidgets('restore button opens the session as a new panel', (
      tester,
    ) async {
      seedHistory();
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final panel = terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpTerminalPanel(tester, panel: panel, cubit: cubit, withBoard: true);

      await openHistoryDialog(tester);
      expect(find.byIcon(Icons.restore), findsOneWidget);

      await tester.tap(find.byIcon(Icons.restore));
      await tester.pump();
      await tester.pump();
      expect(find.text('Terminal history'), findsNothing);
      // The restore path created a new terminal panel on the active board.
      expect(cubit.state.activeBoard!.panels.length, 2);
    });
  });

  group('ensure configured session', () {
    FakeTerminalBackend useFakeBackend() {
      final backend = FakeTerminalBackend();
      addTearDown(backend.closeIfLaunched);
      TerminalBackendService.instance.debugBackendOverride = backend;
      addTearDown(
        () => TerminalBackendService.instance.debugBackendOverride = null,
      );
      return backend;
    }

    testWidgets('configured panel without a session id creates a session', (
      tester,
    ) async {
      useFakeBackend();
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final updates = <Map<String, dynamic>>[];
      final panel = terminalPanel(sessionName: 'demo', workingDir: '/tmp/demo');
      await pumpTerminalPanel(
        tester,
        panel: panel,
        cubit: cubit,
        withBoard: true,
        onUpdateState: updates.add,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The manager spawned (via the fake backend) and the panel switched to
      // the connected view.
      expect(find.byType(TerminalWidget), findsOneWidget);

      // The new config (with the generated session id) was pushed upstream.
      expect(updates, isNotEmpty);
      final config = updates.last['config'] as Map<String, dynamic>;
      expect(config['sessionId'] as String, isNotEmpty);
      expect(config['sessionName'], 'demo');

      // The panel title follows the session display name.
      final updated = cubit.state.activeBoard!.panels.singleWhere(
        (p) => p.id == 'term-panel-1',
      );
      expect(updated.title, 'demo');
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('restores a configured session that is not live yet', (
      tester,
    ) async {
      useFakeBackend();
      final manager = BoardTerminalSessionManager.instance;
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-restore',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
        withBoard: true,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // ensureSession re-spawned the missing session through the backend.
      expect(manager.sessionFor('sess-restore'), isNotNull);
      expect(find.byType(TerminalWidget), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('unconfigured panel skips session resolution on config churn', (
      tester,
    ) async {
      final manager = BoardTerminalSessionManager.instance;
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(sessionName: 'named'),
        cubit: cubit,
      );
      expect(find.text('Create terminal'), findsOneWidget);

      // A config change that keeps the panel unconfigured must early-return
      // from session resolution without touching the manager.
      await tester.pumpWidget(
        buildTerminalPanelApp(
          panel: terminalPanel(sessionName: 'renamed'),
          cubit: cubit,
        ),
      );
      await tester.pump();

      expect(find.text('Create terminal'), findsOneWidget);
      expect(manager.sessionFor(''), isNull);
    });
  });

  group('full view dialog', () {
    testWidgets('opens fullscreen view and exercises its controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
        ),
        cubit: cubit,
      );

      await tester.tap(find.byIcon(Icons.open_in_full_rounded));
      await tester.pump();
      await tester.pump();

      // Two terminals: the panel one and the full-view one.
      expect(find.byType(TerminalWidget), findsNWidgets(2));

      // The debug pane is hidden by default; toggle it on.
      expect(find.text('PgUp'), findsNothing);
      await tester.tap(find.byTooltip('Show debug pane'));
      await tester.pump();
      expect(find.text('PgUp'), findsOneWidget);

      for (final label in [
        'PgUp',
        'PgDn',
        '↑',
        '↓',
        'Copy',
        'Exit',
        'MouseOn',
        'MouseOff',
        'NormBuf',
        'AltBuf',
      ]) {
        await tester.tap(find.text(label));
        await tester.pump();
      }

      // Toggle the forced alt-scroll key fallback.
      expect(find.text('ForceKeysOff'), findsOneWidget);
      await tester.tap(find.text('ForceKeysOff'));
      await tester.pump();
      expect(find.text('ForceKeysOn'), findsOneWidget);
      await tester.tap(find.text('ForceKeysOn'));
      await tester.pump();

      await tester.tap(find.byTooltip('Increase font size'));
      await tester.pump();
      await tester.tap(find.byTooltip('Decrease font size'));
      await tester.pump();

      await tester.tap(find.text('Wheel↑'));
      await tester.pump();
      await tester.tap(find.text('Wheel↓'));
      await tester.pump();

      // Debug log controls.
      await tester.tap(find.byTooltip('Dump terminal state'));
      await tester.pump();
      await tester.tap(find.byTooltip('Copy logs'));
      await tester.pump();
      await tester.tap(find.byTooltip('Clear logs'));
      await tester.pump();

      // Close via the control bar (barrier tap does not dismiss fullscreen).
      await tester.tap(find.byTooltip('Close full view'));
      await tester.pump();
      await tester.pump();
      expect(find.text('PgUp'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });

  group('start session from setup view', () {
    FakeTerminalBackend useBackend({Object? launchError}) {
      final backend = FakeTerminalBackend()..launchError = launchError;
      addTearDown(backend.closeIfLaunched);
      TerminalBackendService.instance.debugBackendOverride = backend;
      addTearDown(
        () => TerminalBackendService.instance.debugBackendOverride = null,
      );
      return backend;
    }

    void stubFolderPicker(String path) {
      BoardFilePicker.debugPickDirectoryOverride = () async => path;
      addTearDown(() => BoardFilePicker.debugPickDirectoryOverride = null);
    }

    Future<void> pickFolderAndStart(WidgetTester tester) async {
      await tester.tap(find.text('Select folder…'));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Start Terminal'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    testWidgets('start creates a session and pushes the config upstream', (
      tester,
    ) async {
      useBackend();
      stubFolderPicker('/tmp/demo');
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final updates = <Map<String, dynamic>>[];
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(),
        cubit: cubit,
        withBoard: true,
        onUpdateState: updates.add,
      );
      expect(find.text('Create terminal'), findsOneWidget);

      await pickFolderAndStart(tester);

      // The session spawned through the fake backend and the connected view
      // replaced the setup form.
      expect(find.byType(TerminalWidget), findsOneWidget);

      // The folder name became the default session name.
      expect(updates, isNotEmpty);
      final config = updates.last['config'] as Map<String, dynamic>;
      expect(config['sessionId'] as String, isNotEmpty);
      expect(config['sessionName'], 'demo');
      expect(config['workingDir'], '/tmp/demo');

      // The panel title follows the session display name.
      final updated = cubit.state.activeBoard!.panels.singleWhere(
        (p) => p.id == 'term-panel-1',
      );
      expect(updated.title, 'demo');
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('start failure shows a snackbar and keeps the setup view', (
      tester,
    ) async {
      useBackend(launchError: StateError('boom'));
      stubFolderPicker('/tmp/demo');
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(),
        cubit: cubit,
        withBoard: true,
      );

      await pickFolderAndStart(tester);

      expect(
        find.textContaining('Could not start terminal'),
        findsOneWidget,
      );
      expect(find.text('Create terminal'), findsOneWidget);
      // Drain the snackbar timer.
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('respawn on env group change', () {
    testWidgets('kills the old session and spawns a new one with the groups', (
      tester,
    ) async {
      final backend = FakeTerminalBackend();
      addTearDown(backend.closeIfLaunched);
      TerminalBackendService.instance.debugBackendOverride = backend;
      addTearDown(
        () => TerminalBackendService.instance.debugBackendOverride = null,
      );
      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', liveTerminalSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final updates = <Map<String, dynamic>>[];
      await pumpTerminalPanel(
        tester,
        panel: terminalPanel(
          sessionId: 'sess-1',
          sessionName: 'demo',
          workingDir: '/tmp/demo',
          envGroupIds: ['g1'],
        ),
        cubit: cubit,
        withBoard: true,
        onUpdateState: updates.add,
      );
      expect(find.byType(TerminalWidget), findsOneWidget);

      // Same session id, different env groups: didUpdateWidget respawns the
      // session. Dropping the last group keeps env resolution offline (an
      // empty id list short-circuits without touching the file system).
      await tester.pumpWidget(
        buildTerminalPanelApp(
          panel: terminalPanel(
            sessionId: 'sess-1',
            sessionName: 'demo',
            workingDir: '/tmp/demo',
          ),
          cubit: cubit,
          onUpdateState: updates.add,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The old session is gone; a fresh one with a new id is live.
      expect(manager.isLive('sess-1'), isFalse);
      expect(updates, isNotEmpty);
      final config = updates.last['config'] as Map<String, dynamic>;
      expect(config['envGroupIds'], isEmpty);
      final newSessionId = config['sessionId'] as String;
      expect(newSessionId, isNot('sess-1'));
      expect(manager.sessionFor(newSessionId), isNotNull);
      expect(find.byType(TerminalWidget), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
