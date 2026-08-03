import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/hotkeys/hotkeys.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/editor/bloc/file_editor_cubit.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/ui/shell/main_shell.dart';

AgentSession _session(String id) {
  return AgentSession(id: id, type: AgentType.copilot, workspacePath: '/repo');
}

class _FakeTerminalCubit extends TerminalCubit {
  _FakeTerminalCubit({List<AgentSession>? sessions})
    : _sessions = sessions ?? [];

  final List<AgentSession> _sessions;
  int activeIndex = 0;
  final List<int> switchedTabs = [];
  final List<String> closedSessions = [];
  final List<String> activeWorkspaces = [];

  @override
  Future<void> initialize() async {
    emit(
      TerminalLoaded(sessions: _sessions, activeIndex: activeIndex),
    );
  }

  void emitLoaded({bool requestOpenPanel = false}) {
    emit(
      TerminalLoaded(
        sessions: _sessions,
        activeIndex: activeIndex,
        requestOpenPanel: requestOpenPanel,
      ),
    );
  }

  @override
  void switchTab(int index) {
    switchedTabs.add(index);
    activeIndex = index;
    emitLoaded();
  }

  @override
  void closeSession(String sessionId) {
    closedSessions.add(sessionId);
  }

  @override
  Future<void> setActiveWorkspace({
    required String workspaceId,
    required String workspacePath,
    List<String>? workspacePaths,
  }) async {
    activeWorkspaces.add(workspaceId);
  }
}

class _FakeWorkspaceCubit extends WorkspaceCubit {
  @override
  Future<void> load() async {
    emit(
      const WorkspaceLoaded(
        workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
        activeWorkspaceId: 'ws-1',
      ),
    );
  }
}

class _FakeReviewCubit extends ReviewCubit {
  final List<List<String>> loadedWorkspacePaths = [];
  final List<String> loadedSessions = [];

  @override
  Future<void> loadWorkspace(List<String> paths, {String? workspaceId}) async {
    loadedWorkspacePaths.add(paths);
  }

  @override
  Future<void> loadSession(List<String> paths, String sessionId) async {
    loadedSessions.add(sessionId);
  }
}

class _FakeRunCubit extends RunCubit {
  final List<String> loadedWorkspaces = [];

  @override
  Future<void> loadForWorkspace(String workspacePath) async {
    loadedWorkspaces.add(workspacePath);
  }
}

class _FakeFileEditorCubit extends FileEditorCubit {
  final List<String> sessions = [];

  @override
  Future<void> setWorkspace(String workspaceId) async {
    sessions.add(workspaceId);
  }

  @override
  Future<void> setSession(String sessionId) async {
    sessions.add(sessionId);
  }
}

class _FakeBoardCubit extends BoardCubit {
  _FakeBoardCubit({
    List<BoardDocument> initialBoards = const [],
    String? initialActiveBoardId,
  }) : _boards = initialBoards,
       _activeBoardId = initialActiveBoardId;

  final List<BoardDocument> _boards;
  final String? _activeBoardId;
  final List<String> activatedBoards = [];
  final List<String> focusedPanels = [];

  @override
  Future<void> load() async {
    emit(
      BoardState(
        boards: _boards,
        activeBoardId: _activeBoardId,
        isLoaded: true,
      ),
    );
  }

  @override
  Future<void> setActiveBoard(String id) async {
    activatedBoards.add(id);
  }

  @override
  Future<void> focusPanel(
    String panelId, {
    String? boardId,
    bool zoomOnFocus = false,
  }) async {
    focusedPanels.add(panelId);
  }
}

Widget _shellApp({
  required _FakeTerminalCubit terminal,
  required _FakeWorkspaceCubit workspace,
  required _FakeReviewCubit review,
  required _FakeRunCubit run,
  required _FakeFileEditorCubit editor,
  required _FakeBoardCubit board,
}) {
  return MultiBlocProvider(
    providers: [
      BlocProvider<WorkspaceCubit>.value(value: workspace),
      BlocProvider<TerminalCubit>.value(value: terminal),
      BlocProvider<ReviewCubit>.value(value: review),
      BlocProvider<FileEditorCubit>.value(value: editor),
      BlocProvider<RunCubit>.value(value: run),
      BlocProvider<BoardCubit>.value(value: board),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: const MainShell(),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({'app.setupCompleted': true});
    await ThemeManager.instance.load();
  });

  group('MainShell', () {
    testWidgets('renders shell with board canvas and resource chip', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final terminal = _FakeTerminalCubit();
      addTearDown(terminal.close);

      await tester.pumpWidget(
        _shellApp(
          terminal: terminal,
          workspace: _FakeWorkspaceCubit(),
          review: _FakeReviewCubit(),
          run: _FakeRunCubit(),
          editor: _FakeFileEditorCubit(),
          board: _FakeBoardCubit(),
        ),
      );
      await tester.pump();

      expect(find.byType(Scaffold), findsOneWidget);
      // Resource chip in the title bar.
      expect(find.byIcon(Icons.memory), findsOneWidget);

      // Drain init timers (setup guide delay, update check delay).
      await tester.pump(const Duration(seconds: 4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('panel toggle intents flip panel visibility', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final terminal = _FakeTerminalCubit();
      addTearDown(terminal.close);

      await tester.pumpWidget(
        _shellApp(
          terminal: terminal,
          workspace: _FakeWorkspaceCubit(),
          review: _FakeReviewCubit(),
          run: _FakeRunCubit(),
          editor: _FakeFileEditorCubit(),
          board: _FakeBoardCubit(),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(Scaffold));

      Actions.invoke(context, const ToggleWorkspacePanelIntent());
      Actions.invoke(context, const ToggleTerminalPanelIntent());
      Actions.invoke(context, const ToggleReviewPanelIntent());
      await tester.pump();
      // Toggling back exercises the closed -> open branch.
      Actions.invoke(context, const ToggleWorkspacePanelIntent());
      Actions.invoke(context, const ToggleTerminalPanelIntent());
      Actions.invoke(context, const ToggleReviewPanelIntent());
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('tab intents drive the terminal cubit', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final terminal = _FakeTerminalCubit(
        sessions: [_session('s1'), _session('s2')],
      );
      addTearDown(terminal.close);

      await tester.pumpWidget(
        _shellApp(
          terminal: terminal,
          workspace: _FakeWorkspaceCubit(),
          review: _FakeReviewCubit(),
          run: _FakeRunCubit(),
          editor: _FakeFileEditorCubit(),
          board: _FakeBoardCubit(),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(Scaffold));

      Actions.invoke(context, const NextAgentTabIntent());
      expect(terminal.switchedTabs, [1]);

      Actions.invoke(context, const PreviousAgentTabIntent());
      // Active tab is now 1 after the switch above; previous wraps to 0.
      expect(terminal.switchedTabs, [1, 0]);

      Actions.invoke(context, const CloseTerminalTabIntent());
      expect(terminal.closedSessions, ['s1']);

      Actions.invoke(context, const FocusTerminalIntent());
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('requestOpenPanel state reopens the agents panel', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final terminal = _FakeTerminalCubit(sessions: [_session('s1')]);
      addTearDown(terminal.close);

      await tester.pumpWidget(
        _shellApp(
          terminal: terminal,
          workspace: _FakeWorkspaceCubit(),
          review: _FakeReviewCubit(),
          run: _FakeRunCubit(),
          editor: _FakeFileEditorCubit(),
          board: _FakeBoardCubit(),
        ),
      );
      await tester.pump();

      final context = tester.element(find.byType(Scaffold));
      Actions.invoke(context, const ToggleTerminalPanelIntent());
      await tester.pump();

      terminal.emitLoaded(requestOpenPanel: true);
      await tester.pump();

      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('resource chip opens and closes the usage overlay', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final terminal = _FakeTerminalCubit();
      addTearDown(terminal.close);

      await tester.pumpWidget(
        _shellApp(
          terminal: terminal,
          workspace: _FakeWorkspaceCubit(),
          review: _FakeReviewCubit(),
          run: _FakeRunCubit(),
          editor: _FakeFileEditorCubit(),
          board: _FakeBoardCubit(
            initialBoards: const [BoardDocument(id: 'b1', name: 'Board 1')],
            initialActiveBoardId: 'b1',
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.byIcon(Icons.memory));
      await tester.pump();

      expect(find.text('RESOURCE USAGE'), findsOneWidget);
      expect(find.text('SYSTEM RAM'), findsOneWidget);
      expect(find.text('BOARDS & PANELS'), findsOneWidget);
      expect(find.text('Board 1'), findsWidgets);

      // Close via the overlay's close icon.
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pump();

      expect(find.text('RESOURCE USAGE'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('openResourceSessionPanel', () {
    Widget harness({required _FakeBoardCubit board}) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: BlocProvider<BoardCubit>.value(
          value: board,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
    }

    testWidgets('focuses the linked panel, switching boards when needed', (
      tester,
    ) async {
      final board = _FakeBoardCubit(
        initialBoards: const [BoardDocument(id: 'b2', name: 'Board 2')],
        initialActiveBoardId: 'b1',
      );
      addTearDown(board.close);

      await tester.pumpWidget(harness(board: board));
      await board.load();
      final context = tester.element(find.byType(Scaffold));

      const session = SessionStat(
        pid: 42,
        label: 'AI Chat',
        cpuPercent: 1,
        memoryBytes: 100,
        metadata: ResourceSessionMetadata(
          kind: 'ai chat',
          boardId: 'b2',
          panelId: 'panel-9',
        ),
      );

      await openResourceSessionPanel(
        context: context,
        boardCubit: board,
        session: session,
      );

      expect(board.activatedBoards, ['b2']);
      expect(board.focusedPanels, ['panel-9']);
    });

    testWidgets('skips board switch when already on the linked board', (
      tester,
    ) async {
      final board = _FakeBoardCubit(
        initialBoards: const [BoardDocument(id: 'b1', name: 'Board 1')],
        initialActiveBoardId: 'b1',
      );
      addTearDown(board.close);

      await tester.pumpWidget(harness(board: board));
      await board.load();
      final context = tester.element(find.byType(Scaffold));

      const session = SessionStat(
        pid: 42,
        label: 'AI Chat',
        cpuPercent: 1,
        memoryBytes: 100,
        metadata: ResourceSessionMetadata(
          kind: 'ai chat',
          boardId: 'b1',
          panelId: 'panel-1',
        ),
      );

      await openResourceSessionPanel(
        context: context,
        boardCubit: board,
        session: session,
      );

      expect(board.activatedBoards, isEmpty);
      expect(board.focusedPanels, ['panel-1']);
    });

    testWidgets('shows a snackbar when no panel is linked', (tester) async {
      final board = _FakeBoardCubit();
      addTearDown(board.close);

      await tester.pumpWidget(harness(board: board));
      final context = tester.element(find.byType(Scaffold));

      const session = SessionStat(
        pid: 42,
        label: 'copilot',
        cpuPercent: 1,
        memoryBytes: 100,
      );

      var closed = false;
      await openResourceSessionPanel(
        context: context,
        boardCubit: board,
        session: session,
        onClose: () => closed = true,
      );
      await tester.pump();

      expect(closed, isTrue);
      expect(board.focusedPanels, isEmpty);
      expect(
        find.text('Could not find a board terminal panel for this process'),
        findsOneWidget,
      );
    });
  });

  group('confirmStopResourceSession', () {
    Widget harness() {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed:
                    () => confirmStopResourceSession(
                      context,
                      const SessionStat(
                        pid: -1,
                        label: 'copilot',
                        cpuPercent: 0,
                        memoryBytes: 0,
                      ),
                    ),
                child: const Text('stop it'),
              );
            },
          ),
        ),
      );
    }

    testWidgets('cancel leaves the session running', (tester) async {
      await tester.pumpWidget(harness());

      await tester.tap(find.text('stop it'));
      await tester.pumpAndSettle();

      expect(find.text('Stop session?'), findsOneWidget);
      expect(find.textContaining('pid -1'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('failed stop surfaces a snackbar', (tester) async {
      await tester.pumpWidget(harness());

      await tester.tap(find.text('stop it'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Stop'));
      await tester.pump();

      // pid -1 cannot be killed -> failure snackbar.
      expect(find.textContaining('Could not stop'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('agents panel listeners', () {
    Widget providerHarness({
      required _FakeTerminalCubit terminal,
      required _FakeWorkspaceCubit workspace,
      required _FakeReviewCubit review,
      required _FakeRunCubit run,
      required _FakeFileEditorCubit editor,
      required _FakeBoardCubit board,
    }) {
      return MultiBlocProvider(
        providers: [
          BlocProvider<WorkspaceCubit>.value(value: workspace),
          BlocProvider<TerminalCubit>.value(value: terminal),
          BlocProvider<ReviewCubit>.value(value: review),
          BlocProvider<FileEditorCubit>.value(value: editor),
          BlocProvider<RunCubit>.value(value: run),
          BlocProvider<BoardCubit>.value(value: board),
        ],
        child: MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );
    }

    testWidgets('handleAgentSessionChanged syncs cubits', (tester) async {
      final terminal = _FakeTerminalCubit();
      final workspace = _FakeWorkspaceCubit();
      final review = _FakeReviewCubit();
      final run = _FakeRunCubit();
      final editor = _FakeFileEditorCubit();
      final board = _FakeBoardCubit();
      addTearDown(terminal.close);
      addTearDown(workspace.close);
      addTearDown(review.close);
      addTearDown(run.close);
      addTearDown(editor.close);
      addTearDown(board.close);

      await tester.pumpWidget(
        providerHarness(
          terminal: terminal,
          workspace: workspace,
          review: review,
          run: run,
          editor: editor,
          board: board,
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));

      // Non-loaded state is ignored.
      handleAgentSessionChanged(context, const TerminalInitial());
      expect(review.loadedSessions, isEmpty);

      // Loaded state without sessions is ignored.
      handleAgentSessionChanged(
        context,
        const TerminalLoaded(sessions: [], activeIndex: 0),
      );
      expect(review.loadedSessions, isEmpty);

      // Active session syncs review + editor; empty paths skip run reload.
      handleAgentSessionChanged(
        context,
        TerminalLoaded(sessions: [_session('s1')], activeIndex: 0),
      );
      expect(review.loadedSessions, ['s1']);
      expect(editor.sessions, ['s1']);
      // Workspace cubit is still initial -> no paths -> no run reload.
      expect(run.loadedWorkspaces, isEmpty);
    });

    testWidgets('handleAgentWorkspaceChanged reinitializes cubits', (
      tester,
    ) async {
      final terminal = _FakeTerminalCubit();
      final workspace = _FakeWorkspaceCubit();
      final review = _FakeReviewCubit();
      final run = _FakeRunCubit();
      final editor = _FakeFileEditorCubit();
      final board = _FakeBoardCubit();
      addTearDown(terminal.close);
      addTearDown(workspace.close);
      addTearDown(review.close);
      addTearDown(run.close);
      addTearDown(editor.close);
      addTearDown(board.close);

      await tester.pumpWidget(
        providerHarness(
          terminal: terminal,
          workspace: workspace,
          review: review,
          run: run,
          editor: editor,
          board: board,
        ),
      );
      await tester.pump();
      final context = tester.element(find.byType(Scaffold));

      // Non-loaded state is ignored.
      handleAgentWorkspaceChanged(context, const WorkspaceLoading());
      expect(terminal.activeWorkspaces, isEmpty);

      // Loaded state without active workspace is ignored.
      handleAgentWorkspaceChanged(
        context,
        const WorkspaceLoaded(
          workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
        ),
      );
      expect(terminal.activeWorkspaces, isEmpty);

      // Active workspace reinitializes terminal, run, review, editor.
      handleAgentWorkspaceChanged(
        context,
        const WorkspaceLoaded(
          workspaces: [Workspace(id: 'ws-1', name: 'One', paths: ['/a'])],
          activeWorkspaceId: 'ws-1',
        ),
      );
      expect(terminal.activeWorkspaces, ['ws-1']);
      expect(run.loadedWorkspaces, ['/a']);
      expect(review.loadedWorkspacePaths, [
        ['/a'],
      ]);
      expect(editor.sessions, ['ws-1']);
    });
  });
}
