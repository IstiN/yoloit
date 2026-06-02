import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Overrides [renameSession] so it updates state directly without needing
/// [_allSessions] to be populated (which requires a real PTY session).
class _FakeTerminalCubit extends TerminalCubit {
  @override
  void renameSession(String sessionId, String name) {
    final current = state;
    if (current is! TerminalLoaded) return;
    final updated =
        current.sessions.map((s) {
          if (s.id != sessionId) return s;
          return name.trim().isEmpty
              ? s.copyWith(clearCustomName: true)
              : s.copyWith(customName: name.trim());
        }).toList();
    emit(current.copyWith(sessions: updated, allSessions: updated));
  }
}

Widget _buildTerminalTest({
  required TerminalState terminalState,
  WorkspaceState? workspaceState,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<TerminalCubit>(
        create: (_) => TerminalCubit()..emit(terminalState),
      ),
      BlocProvider<WorkspaceCubit>(
        create: (_) {
          final cubit = WorkspaceCubit();
          if (workspaceState != null) cubit.emit(workspaceState);
          return cubit;
        },
      ),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const Scaffold(body: TerminalPanel()),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  void useXtermRenderer() {
    AgentConfigService.instance.setTerminalRenderEngineForTesting(
      TerminalRenderEngine.xterm,
    );
  }

  group('TerminalPanel widget tests', () {
    testWidgets('empty state shows AI Agents header', (tester) async {
      await tester.pumpWidget(
        _buildTerminalTest(terminalState: const TerminalInitial()),
      );
      await tester.pump();

      expect(find.text('AI Agents'), findsAtLeastNWidgets(1));
    });

    testWidgets('empty state shows instruction text', (tester) async {
      await tester.pumpWidget(
        _buildTerminalTest(terminalState: const TerminalInitial()),
      );
      await tester.pump();

      expect(
        find.text('Open a workspace and start an AI agent to begin'),
        findsOneWidget,
      );
    });

    testWidgets('shows launch buttons when workspace is active', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTerminalTest(
          terminalState: const TerminalInitial(),
          workspaceState: const WorkspaceLoaded(
            workspaces: [
              Workspace(id: 'ws_1', name: 'proj', paths: ['/proj']),
            ],
            activeWorkspaceId: 'ws_1',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Copilot'), findsWidgets);
      expect(find.text('Claude'), findsWidgets);
    });

    testWidgets('shows select workspace hint when no active workspace', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildTerminalTest(
          terminalState: const TerminalLoaded(sessions: [], activeIndex: 0),
          workspaceState: const WorkspaceLoaded(workspaces: []),
        ),
      );
      await tester.pump();

      expect(
        find.text('Select a workspace from the left panel first'),
        findsOneWidget,
      );
    });

    testWidgets('tab shows default agent name', (tester) async {
      final session = AgentSession(
        id: 'sess_1',
        type: AgentType.copilot,
        workspacePath: '/project',
        workspaceId: 'ws_1',
      );
      await tester.pumpWidget(
        _buildTerminalTest(
          terminalState: TerminalLoaded(sessions: [session], activeIndex: 0),
        ),
      );
      await tester.pump();

      expect(find.text('Copilot'), findsAtLeastNWidgets(1));
    });

    testWidgets('tab shows custom name when set via copyWith', (tester) async {
      final session = AgentSession(
        id: 'sess_1',
        type: AgentType.copilot,
        workspacePath: '/project',
        workspaceId: 'ws_1',
      ).copyWith(customName: 'story/MAPC-6809');
      await tester.pumpWidget(
        _buildTerminalTest(
          terminalState: TerminalLoaded(sessions: [session], activeIndex: 0),
        ),
      );
      await tester.pump();

      expect(find.text('story/MAPC-6809'), findsOneWidget);
    });

    testWidgets('double-tap on tab enters rename mode (shows TextField)', (
      tester,
    ) async {
      final session = AgentSession(
        id: 'sess_1',
        type: AgentType.copilot,
        workspacePath: '/project',
        workspaceId: 'ws_1',
      );
      await tester.pumpWidget(
        _buildTerminalTest(
          terminalState: TerminalLoaded(sessions: [session], activeIndex: 0),
        ),
      );
      await tester.pump();

      // Use GestureDetector's onDoubleTap — need to simulate a proper double-tap
      await tester.tap(find.text('Copilot'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Copilot'));
      // Drain the double-tap countdown timer (300ms)
      await tester.pump(const Duration(milliseconds: 350));

      // A TextField should appear in the tab
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets(
      'entering name in rename field and submitting exits edit mode',
      (tester) async {
        final session = AgentSession(
          id: 'sess_1',
          type: AgentType.copilot,
          workspacePath: '/project',
          workspaceId: 'ws_1',
        );
        await tester.pumpWidget(
          _buildTerminalTest(
            terminalState: TerminalLoaded(sessions: [session], activeIndex: 0),
          ),
        );
        await tester.pump();

        // Double-tap to enter rename mode
        await tester.tap(find.text('Copilot'));
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.text('Copilot'));
        await tester.pump(const Duration(milliseconds: 350));
        expect(find.byType(TextField), findsOneWidget);

        // Type new name and submit — edit mode should exit (TextField gone)
        await tester.enterText(find.byType(TextField), 'my-feature');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pump();

        expect(find.byType(TextField), findsNothing);
      },
    );

    testWidgets('tab shows custom name after rename via cubit', (tester) async {
      final session = AgentSession(
        id: 'sess_1',
        type: AgentType.copilot,
        workspacePath: '/project',
        workspaceId: 'ws_1',
      );
      final fakeCubit =
          _FakeTerminalCubit()
            ..emit(TerminalLoaded(sessions: [session], activeIndex: 0));

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TerminalCubit>.value(value: fakeCubit),
            BlocProvider<WorkspaceCubit>(create: (_) => WorkspaceCubit()),
          ],
          child: MaterialApp(
            theme: AppThemePreset.neonPurple.theme,
            home: const Scaffold(body: TerminalPanel()),
          ),
        ),
      );
      await tester.pump();

      // Double-tap to enter rename mode
      await tester.tap(find.text('Copilot'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Copilot'));
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.byType(TextField), findsOneWidget);

      // Enter new name and submit
      await tester.enterText(find.byType(TextField), 'my-task');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();

      // Fake cubit updates state — tab should now show the custom name
      expect(find.text('my-task'), findsOneWidget);
    });

    testWidgets('terminal widget disables scroll-to-arrow fallback', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_scroll',
        type: AgentType.copilot,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TerminalWidget(session: session, isActive: true),
          ),
        ),
      );
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      expect(terminalView.simulateScroll, isFalse);
    });

    testWidgets('terminal widget scrolls on trackpad pan-zoom updates', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_trackpad_scroll',
        type: AgentType.copilot,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 140,
              child: TerminalWidget(session: session, isActive: true),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 80; i++) {
        session.terminal.write('line $i\r\n');
      }
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final scrollController = terminalView.scrollController!;
      expect(scrollController.position.maxScrollExtent, greaterThan(0));

      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      final before = scrollController.offset;
      final position = tester.getCenter(find.byType(TerminalView));

      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 1, position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 1,
          position: position,
          panDelta: const Offset(0, 40),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump();

      expect(scrollController.offset, lessThan(before));
    });

    testWidgets('terminal widget quick actions scroll scrollback locally', (
      tester,
    ) async {
      useXtermRenderer();
      final outputs = <String>[];
      final key = GlobalKey<TerminalWidgetState>();
      final session = AgentSession(
        id: 'sess_quick_scroll',
        type: AgentType.copilot,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 140,
              child: TerminalWidget(
                key: key,
                session: session,
                isActive: true,
                terminalOutputWriter: (sessionId, data) => outputs.add(data),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 80; i++) {
        session.terminal.write('line $i\r\n');
      }
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final scrollController = terminalView.scrollController!;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final bottom = scrollController.offset;
      key.currentState!.scrollPageUp();
      await tester.pump();
      expect(scrollController.offset, lessThan(bottom));

      key.currentState!.scrollPageDown();
      await tester.pump();
      expect(scrollController.offset, bottom);
      expect(outputs, isEmpty);
    });

    testWidgets('terminal widget exposes a wide draggable scrollbar', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_scrollbar',
        type: AgentType.copilot,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 140,
              child: TerminalWidget(session: session, isActive: true),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 80; i++) {
        session.terminal.write('line $i\r\n');
      }
      await tester.pump();

      final scrollbar = tester.widget<RawScrollbar>(find.byType(RawScrollbar));
      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      expect(scrollbar.interactive, isTrue);
      expect(scrollbar.thumbVisibility, isTrue);
      expect(scrollbar.trackVisibility, isTrue);
      expect(scrollbar.thickness, 14);
      expect(scrollbar.controller, same(terminalView.scrollController));
    });

    testWidgets('terminal single click does not send cursor movement', (
      tester,
    ) async {
      useXtermRenderer();
      final outputs = <String>[];
      final session = AgentSession(
        id: 'sess_click_no_cursor_jump',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      session.terminal.write('prompt> abc');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 140,
              child: TerminalWidget(
                session: session,
                isActive: true,
                terminalOutputWriter: (sessionId, data) => outputs.add(data),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tapAt(tester.getCenter(find.byType(TerminalView)));
      await tester.pump(const Duration(milliseconds: 350));

      expect(outputs, isEmpty);
    });

    testWidgets('alt-buffer pan-zoom scroll sends key fallback without mouse', (
      tester,
    ) async {
      useXtermRenderer();
      final outputs = <String>[];
      final session = AgentSession(
        id: 'sess_alt_scroll',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      session.terminal.useAltBuffer();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 140,
              child: TerminalWidget(
                session: session,
                isActive: true,
                terminalOutputWriter: (sessionId, data) => outputs.add(data),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final position = tester.getCenter(find.byType(TerminalView));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 1, position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 1,
          position: position,
          panDelta: const Offset(0, 80),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump();

      expect(outputs, isNotEmpty);
      expect(outputs.join(), contains('\x1B[A'));
    });
  });
}
