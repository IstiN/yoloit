import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
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

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    CanvasInteractionLock.instance.resetForTesting();
  });

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
      // Two pumps are required because xterm render.dart now batches
      // layout updates via addPostFrameCallback.
      await tester.pump();
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

    testWidgets('terminal keeps user scroll position during live output', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_live_output_scroll_lock',
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
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final bottom = scrollController.offset;
      final position = tester.getCenter(find.byType(TerminalView));
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 1, position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 1,
          position: position,
          panDelta: const Offset(0, 48),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump();

      final userOffset = scrollController.offset;
      expect(userOffset, lessThan(bottom));

      for (var i = 80; i < 110; i++) {
        session.terminal.write('line $i\r\n');
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump(const Duration(milliseconds: 120));

      expect(scrollController.offset, closeTo(userOffset, 1.0));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 950));
    });

    testWidgets('terminal ignores horizontal trackpad pan-zoom scrollback', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_horizontal_trackpad_scroll',
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
          panDelta: const Offset(80, 4),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(scrollController.offset, before);
    });

    testWidgets('terminal ignores horizontal pointer signal scrollback', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_horizontal_pointer_signal',
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
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final before = scrollController.offset;
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: tester.getCenter(find.byType(TerminalView)),
          scrollDelta: const Offset(80, 4),
        ),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(scrollController.offset, before);
    });

    testWidgets(
      'terminal scrolls on mouse wheel even while canvas gesture is active',
      (tester) async {
        useXtermRenderer();
        final session = AgentSession(
          id: 'sess_mouse_wheel_canvas_gesture',
          type: AgentType.terminal,
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
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
        await tester.pump();

        final before = scrollController.offset;
        CanvasInteractionLock.instance.beginCanvasGesture();
        await tester.sendEventToBinding(
          PointerScrollEvent(
            kind: PointerDeviceKind.mouse,
            position: tester.getCenter(find.byType(TerminalView)),
            scrollDelta: const Offset(0, -40),
          ),
        );
        await tester.pump(const Duration(milliseconds: 220));
        CanvasInteractionLock.instance.endCanvasGesture();

        expect(scrollController.offset, lessThan(before));
      },
    );

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

      final terminalRect = tester.getRect(find.byType(TerminalView));
      final dragStart = Offset(terminalRect.right - 6, terminalRect.top + 40);
      final gesture = await tester.startGesture(dragStart);
      await gesture.moveBy(const Offset(0, 50));
      await gesture.up();
      await tester.pump();

      expect(terminalView.controller?.selection, isNull);
    });

    testWidgets('terminal resize keeps scrollback anchored to bottom', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_resize_scroll_anchor',
        type: AgentType.copilot,
        workspacePath: '/project',
      );

      Widget buildTerminal(double height) {
        return MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: height,
              child: TerminalWidget(session: session, isActive: true),
            ),
          ),
        );
      }

      await tester.pumpWidget(buildTerminal(140));
      await tester.pump();

      for (var i = 0; i < 100; i++) {
        session.terminal.write('line $i\r\n');
      }
      await tester.pump();

      var terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
      final scrollController = terminalView.scrollController!;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );

      await tester.pumpWidget(buildTerminal(260));
      await tester.pump();
      await tester.pump();

      terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
      expect(terminalView.scrollController, same(scrollController));
      expect(
        scrollController.offset,
        scrollController.position.maxScrollExtent,
      );
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

    test('terminalUrlAtCell returns trimmed URL under clicked cell', () {
      const line =
          'Release https://github.com/IstiN/yoloit/releases/tag/v1.0.146.';

      expect(
        terminalUrlAtCell(line, line.indexOf('github.com') + 2),
        'https://github.com/IstiN/yoloit/releases/tag/v1.0.146',
      );
      expect(terminalUrlAtCell(line, 0), isNull);
    });

    test('terminalUrlAtWrappedCell joins soft-wrapped URL lines', () {
      const lines = [
        TerminalUrlLine('Release https://github.com/IstiN/yol'),
        TerminalUrlLine('oit/releases/tag/v1.0.146', isWrapped: true),
        TerminalUrlLine('. done', isWrapped: true),
      ];

      expect(
        terminalUrlAtWrappedCell(lines, 1, 4),
        'https://github.com/IstiN/yoloit/releases/tag/v1.0.146',
      );
      expect(
        terminalUrlAtWrappedCell(lines, 1, 12),
        'https://github.com/IstiN/yoloit/releases/tag/v1.0.146',
      );
      expect(terminalUrlAtWrappedCell(lines, 2, 0), isNull);
      expect(terminalUrlAtWrappedCell(lines, 0, 0), isNull);
    });

    testWidgets('terminal single click opens URL under pointer', (
      tester,
    ) async {
      useXtermRenderer();
      final opened = <String>[];
      final outputs = <String>[];
      final session = AgentSession(
        id: 'sess_click_url',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      const url = 'https://github.com/IstiN/yoloit/releases/tag/v1.0.146';
      session.terminal.write('Release $url.\r\n');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 180,
              child: TerminalWidget(
                session: session,
                isActive: true,
                terminalOutputWriter: (sessionId, data) => outputs.add(data),
                linkOpener: (url) => opened.add(url),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final viewState = tester.state<TerminalViewState>(
        find.byType(TerminalView),
      );
      final renderTerminal = viewState.renderTerminal;
      // Column 18 sits inside the URL after "Release https://".
      const cell = CellOffset(18, 0);
      final local =
          renderTerminal.getOffset(cell) +
          const Offset(2, 0) +
          Offset(0, renderTerminal.lineHeight / 2);
      final global = renderTerminal.localToGlobal(local);

      await tester.tapAt(global);
      await tester.pump(const Duration(milliseconds: 350));

      expect(opened, [url]);
      expect(outputs, isEmpty);
    });

    testWidgets('terminal click opens soft-wrapped URL under pointer', (
      tester,
    ) async {
      useXtermRenderer();
      final opened = <String>[];
      final outputs = <String>[];
      final session = AgentSession(
        id: 'sess_click_wrapped_url',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      const url = 'https://github.com/IstiN/yoloit/releases/tag/v1.0.146';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 260,
              height: 180,
              child: TerminalWidget(
                session: session,
                isActive: true,
                terminalOutputWriter: (sessionId, data) => outputs.add(data),
                linkOpener: (url) => opened.add(url),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      session.terminal.write('Release $url.\r\n');
      await tester.pump();

      final bufferLines = session.terminal.buffer.lines;
      final lines = List<TerminalUrlLine>.generate(bufferLines.length, (index) {
        final line = bufferLines[index];
        return TerminalUrlLine(line.toString(), isWrapped: line.isWrapped);
      }, growable: false);
      CellOffset? clickedCell;
      for (var y = 0; y < lines.length && clickedCell == null; y++) {
        for (var x = 0; x < lines[y].text.length; x++) {
          if (terminalUrlAtWrappedCell(lines, y, x) == url &&
              lines[y].isWrapped) {
            clickedCell = CellOffset(x, y);
            break;
          }
        }
      }
      expect(clickedCell, isNotNull);

      final viewState = tester.state<TerminalViewState>(
        find.byType(TerminalView),
      );
      final renderTerminal = viewState.renderTerminal;
      // This cell is inside a continuation row of the same soft-wrapped
      // URL. The opener must receive the entire URL, not only row 1.
      final local =
          renderTerminal.getOffset(clickedCell!) +
          const Offset(2, 0) +
          Offset(0, renderTerminal.lineHeight / 2);
      final global = renderTerminal.localToGlobal(local);

      await tester.tapAt(global);
      await tester.pump(const Duration(milliseconds: 350));

      expect(opened, [url]);
      expect(outputs, isEmpty);
    });

    testWidgets('canvas-owned pan zoom does not scroll terminal scrollback', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'terminal_canvas_pan_guard',
        type: AgentType.terminal,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 180,
              child: TerminalWidget(session: session, isActive: true),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 90; i++) {
        session.terminal.write('history-line-$i\r\n');
      }
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final scrollController = terminalView.scrollController!;
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
      await tester.pump();

      final before = scrollController.offset;
      final position = tester.getCenter(find.byType(TerminalView));
      CanvasInteractionLock.instance.beginCanvasGesture();
      await tester.sendEventToBinding(
        PointerPanZoomStartEvent(pointer: 1, position: position),
      );
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 1,
          position: position,
          panDelta: const Offset(0, 96),
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump();
      CanvasInteractionLock.instance.endCanvasGesture();

      expect(scrollController.offset, before);
    });

    testWidgets('pinch scale over terminal does not scroll scrollback', (
      tester,
    ) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'terminal_pinch_zoom_guard',
        type: AgentType.terminal,
        workspacePath: '/project',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: Scaffold(
            body: SizedBox(
              width: 520,
              height: 180,
              child: TerminalWidget(session: session, isActive: true),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 90; i++) {
        session.terminal.write('history-line-$i\r\n');
      }
      await tester.pump();

      final terminalView = tester.widget<TerminalView>(
        find.byType(TerminalView),
      );
      final scrollController = terminalView.scrollController!;
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
          panDelta: const Offset(0, 96),
          scale: 1.2,
        ),
      );
      await tester.sendEventToBinding(
        PointerPanZoomEndEvent(pointer: 1, position: position),
      );
      await tester.pump(const Duration(milliseconds: 220));

      expect(scrollController.offset, before);
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

    testWidgets('persists scroll offset across widget rebuilds', (tester) async {
      useXtermRenderer();
      final session = AgentSession(
        id: 'sess_scroll_persist',
        type: AgentType.terminal,
        workspacePath: '/project',
      );
      // Fill terminal with enough lines to make it scrollable.
      for (var i = 0; i < 100; i++) {
        session.terminal.write('line $i\n');
      }

      // Pre-seed scroll offset so the widget restores it on creation.
      session.scrollOffset = 150.0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              child: TerminalWidget(
                session: session,
                isActive: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final scrollable = find.byType(Scrollable);
      final controller = tester.widget<Scrollable>(scrollable).controller;
      expect(controller?.hasClients, isTrue);
      // The offset should reflect the restored scroll position.
      expect(controller?.offset, 150.0);

      // Update scroll position and verify it is persisted via listener.
      controller?.jumpTo(200.0);
      await tester.pump();
      expect(session.scrollOffset, 200.0);

      // Dispose and recreate — new controller should start at 200.0.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              child: Container(),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 200,
              child: TerminalWidget(
                session: session,
                isActive: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final newScrollable = find.byType(Scrollable);
      final newController = tester.widget<Scrollable>(newScrollable).controller;
      expect(newController?.hasClients, isTrue);
      expect(newController?.offset, 200.0);
    });

    testWidgets('only active session is rendered in Stack', (tester) async {
      useXtermRenderer();
      final s1 = AgentSession(
        id: 'sess_a',
        type: AgentType.terminal,
        workspacePath: '/p1',
      );
      final s2 = AgentSession(
        id: 'sess_b',
        type: AgentType.terminal,
        workspacePath: '/p2',
      );

      final cubit = _FakeTerminalCubit()
        ..emit(
          TerminalLoaded(
            sessions: [s1, s2],
            activeIndex: 0,
          ),
        );

      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<TerminalCubit>(create: (_) => cubit),
            BlocProvider<WorkspaceCubit>(create: (_) => WorkspaceCubit()),
          ],
          child: MaterialApp(
            theme: AppThemePreset.neonPurple.theme,
            home: const Scaffold(body: TerminalPanel()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Only one TerminalWidget should exist in the tree.
      expect(find.byType(TerminalWidget), findsOneWidget);

      // Switch to second session.
      cubit.emit(
        TerminalLoaded(
          sessions: [s1, s2],
          activeIndex: 1,
        ),
      );
      await tester.pumpAndSettle();

      // Still only one TerminalWidget.
      expect(find.byType(TerminalWidget), findsOneWidget);
    });
  });
}
