import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/board/terminal/board_terminal_panel_widget.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

BoardPanelInstance _terminalPanel({
  String sessionId = '',
  String sessionName = '',
  String workingDir = '',
  List<String> envGroupIds = const [],
}) {
  return BoardPanelInstance(
    id: 'term-panel-1',
    type: kTerminalPluginTypeId,
    title: 'Terminal',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 520, height: 400),
    state: {
      'config': {
        'sessionId': sessionId,
        'sessionName': sessionName,
        'workingDir': workingDir,
        'envGroupIds': envGroupIds,
      },
    },
  );
}

AgentSession _liveSession(
  String id, {
  String name = 'demo',
  String dir = '/tmp/demo',
}) {
  return AgentSession(
    id: id,
    type: AgentType.terminal,
    workspacePath: dir,
    status: AgentStatus.live,
    customName: name,
  );
}

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

  Widget buildApp({
    required BoardPanelInstance panel,
    required BoardCubit cubit,
    ValueChanged<Map<String, dynamic>>? onUpdateState,
  }) {
    // BoardCubit sits above the MaterialApp so dialogs pushed onto the root
    // navigator (e.g. the session history dialog) can also read it.
    return BlocProvider<BoardCubit>.value(
      value: cubit,
      child: MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 560,
            height: 480,
            child: BoardTerminalPanelWidget(
              panel: panel,
              onUpdateState: onUpdateState ?? (_) {},
            ),
          ),
        ),
      ),
    );
  }

  Future<void> pumpPanel(
    WidgetTester tester, {
    required BoardPanelInstance panel,
    BoardCubit? cubit,
    ValueChanged<Map<String, dynamic>>? onUpdateState,
    bool withBoard = false,
  }) async {
    final boardCubit = cubit ?? BoardCubit();
    if (withBoard) {
      boardCubit.emit(
        BoardState(
          boards: [
            BoardDocument(id: 'b1', name: 'Board 1', panels: [panel]),
          ],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );
    }
    await tester.pumpWidget(
      buildApp(panel: panel, cubit: boardCubit, onUpdateState: onUpdateState),
    );
    await tester.pump();
  }

  group('setup view', () {
    testWidgets('unconfigured panel shows create terminal form', (
      tester,
    ) async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(tester, panel: _terminalPanel(), cubit: cubit);

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
      await pumpPanel(
        tester,
        panel: _terminalPanel(sessionName: 'named'),
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);

      final panelV1 = _terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpPanel(tester, panel: panelV1, cubit: cubit);
      expect(find.text('/tmp/demo'), findsOneWidget);

      // Same session id, different name: didUpdateWidget re-reads the config
      // and resolves the already-live session again.
      final panelV2 = _terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'renamed',
        workingDir: '/tmp/demo',
      );
      await tester.pumpWidget(buildApp(panel: panelV2, cubit: cubit));
      await tester.pump();
      expect(find.byType(TerminalWidget), findsOneWidget);

      // Swapping the session object under the same id notifies the manager
      // listener and re-attaches the info bar terminal listener.
      manager.setSessionForTesting(
        'sess-1',
        _liveSession('sess-1', name: 'demo2'),
      );
      await tester.pump();
      expect(find.byType(TerminalWidget), findsOneWidget);
    });

    testWidgets('TUI badge reflects alt-buffer changes', (tester) async {
      final manager = BoardTerminalSessionManager.instance;
      final session = _liveSession('sess-1');
      manager.setSessionForTesting('sess-1', session);
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      final session = _liveSession('sess-1');
      manager.setSessionForTesting('sess-1', session);
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final panel = _terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpPanel(tester, panel: panel, cubit: cubit, withBoard: true);
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final panel = _terminalPanel(
        sessionId: 'sess-1',
        sessionName: 'demo',
        workingDir: '/tmp/demo',
      );
      await pumpPanel(tester, panel: panel, cubit: cubit, withBoard: true);

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

  group('full view dialog', () {
    testWidgets('opens debug overlay and exercises its controls', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final manager = BoardTerminalSessionManager.instance;
      manager.setSessionForTesting('sess-1', _liveSession('sess-1'));
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      await pumpPanel(
        tester,
        panel: _terminalPanel(
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

      await tester.tap(find.text('Font+'));
      await tester.pump();
      await tester.tap(find.text('Font-'));
      await tester.pump();

      await tester.tap(find.text('Wheel↑'));
      await tester.pump();
      await tester.tap(find.text('Wheel↓'));
      await tester.pump();

      // Debug log controls.
      await tester.tap(find.byIcon(Icons.bug_report));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.copy));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.clear_all));
      await tester.pump();

      // Dismiss via the barrier (dialog is 1000x800 on a 1600x1200 surface).
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      await tester.pump();
      expect(find.text('PgUp'), findsNothing);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
