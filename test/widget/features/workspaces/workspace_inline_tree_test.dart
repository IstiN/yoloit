import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/review/bloc/review_cubit.dart';
import 'package:yoloit/features/runs/bloc/run_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/workspace_inline_tree.dart';

class _FakeWorktreeService implements WorktreeService {
  _FakeWorktreeService(this.worktreesByRepo);

  final Map<String, List<WorktreeEntry>> worktreesByRepo;

  @override
  Future<List<WorktreeEntry>> listWorktrees(String repoPath) async =>
      worktreesByRepo[repoPath] ?? const [];

  @override
  Future<String?> addWorktree(
    String repoPath,
    String worktreePath,
    String branchOrCommit, {
    bool createNewBranch = false,
  }) async =>
      null;

  @override
  Future<String?> removeWorktree(
    String repoPath,
    String worktreePath, {
    bool force = false,
  }) async =>
      null;

  @override
  Future<void> pruneWorktrees(String repoPath) async {}

  @override
  Future<List<String>> listBranches(String repoPath) async => const [];
}

const _testWorkspace = Workspace(
  id: 'ws_test',
  name: 'test-project',
  paths: ['/fake/repo-a', '/fake/repo-b'],
);

const _otherWorkspace = Workspace(
  id: 'ws_other',
  name: 'other-project',
  paths: ['/fake/other'],
);

Widget _buildTest({
  Workspace workspace = _testWorkspace,
  TerminalState? termState,
}) {
  final ts = termState ?? const TerminalLoaded(sessions: [], activeIndex: 0, allSessions: []);
  return MultiBlocProvider(
    providers: [
      BlocProvider<WorkspaceCubit>(
        create: (_) => WorkspaceCubit()
          ..emit(WorkspaceLoaded(
            workspaces: [workspace, _otherWorkspace],
            activeWorkspaceId: workspace.id,
          )),
      ),
      BlocProvider<TerminalCubit>(create: (_) => TerminalCubit()..emit(ts)),
      BlocProvider<ReviewCubit>(create: (_) => ReviewCubit()),
      BlocProvider<RunCubit>(create: (_) => RunCubit()),
    ],
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: WorkspaceInlineTree(workspace: workspace),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('WorkspaceInlineTree widget tests', () {
    testWidgets('shows nothing initially while loading', (tester) async {
      await tester.pumpWidget(_buildTest());

      // During loading phase, widget returns SizedBox.shrink()
      expect(find.text('repo-a'), findsNothing);
      expect(find.text('repo-b'), findsNothing);

      // Let async worktree loading complete to avoid pending timers
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('shows "＋ New Agent Session" button after load', (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('＋ New Agent Session'), findsOneWidget);
    });

    testWidgets('shows no repo names when there are no sessions', (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      // Repo names only appear inside session cards, not without a session
      expect(find.text('repo-a'), findsNothing);
      expect(find.text('repo-b'), findsNothing);
    });

    testWidgets('shows repo names inside session card when session exists', (tester) async {
      final session = AgentSession(
        id: 'sess_ws_test',
        type: AgentType.copilot,
        workspacePath: '/fake/repo-a',
        workspaceId: 'ws_test',
      );
      final termState = TerminalLoaded(
        sessions: [session],
        activeIndex: 0,
        allSessions: [session],
      );

      await tester.pumpWidget(_buildTest(termState: termState));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('repo-a'), findsOneWidget);
      expect(find.text('repo-b'), findsOneWidget);
    });

    testWidgets('shows agent sessions that belong to the workspace', (tester) async {
      final session = AgentSession(
        id: 'sess_ws_test',
        type: AgentType.claude,
        workspacePath: '/fake/repo-a',
        workspaceId: 'ws_test',
        customName: 'my-claude-session',
      );
      final termState = TerminalLoaded(
        sessions: [session],
        activeIndex: 0,
        allSessions: [session],
      );

      await tester.pumpWidget(_buildTest(termState: termState));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('my-claude-session'), findsOneWidget);
    });

    testWidgets('shows agent type display name for session without custom name', (tester) async {
      final session = AgentSession(
        id: 'sess_copilot',
        type: AgentType.copilot,
        workspacePath: '/fake/repo-a',
        workspaceId: 'ws_test',
      );
      final termState = TerminalLoaded(
        sessions: [session],
        activeIndex: 0,
        allSessions: [session],
      );

      await tester.pumpWidget(_buildTest(termState: termState));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Copilot'), findsOneWidget);
    });

    testWidgets('does NOT show agent sessions from other workspaces', (tester) async {
      final sessionOther = AgentSession(
        id: 'sess_other',
        type: AgentType.copilot,
        workspacePath: '/fake/other',
        workspaceId: 'ws_other',
        customName: 'other-workspace-session',
      );
      final termState = TerminalLoaded(
        sessions: [sessionOther],
        activeIndex: 0,
        allSessions: [sessionOther],
      );

      await tester.pumpWidget(_buildTest(termState: termState));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('other-workspace-session'), findsNothing);
    });

    testWidgets('shows only sessions for the current workspace, not from other workspaces',
        (tester) async {
      final sessionThis = AgentSession(
        id: 'sess_this',
        type: AgentType.claude,
        workspacePath: '/fake/repo-a',
        workspaceId: 'ws_test',
        customName: 'this-session',
      );
      final sessionOther = AgentSession(
        id: 'sess_other',
        type: AgentType.copilot,
        workspacePath: '/fake/other',
        workspaceId: 'ws_other',
        customName: 'other-session',
      );
      final termState = TerminalLoaded(
        sessions: [sessionThis, sessionOther],
        activeIndex: 0,
        allSessions: [sessionThis, sessionOther],
      );

      await tester.pumpWidget(_buildTest(termState: termState));
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('this-session'), findsOneWidget);
      expect(find.text('other-session'), findsNothing);
    });

    testWidgets('tapping "＋ New Agent Session" opens dialog with "New Agent Session" text',
        (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('＋ New Agent Session'));
      await tester.pumpAndSettle();

      expect(find.text('New Agent Session'), findsOneWidget);
    });

    testWidgets('dialog opened by "＋ New Agent Session" has "Cancel" and "Start" buttons',
        (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('＋ New Agent Session'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Start'), findsOneWidget);
    });

    testWidgets('dialog has Agent Type dropdown', (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('＋ New Agent Session'));
      await tester.pumpAndSettle();

      expect(find.text('Agent Type'), findsOneWidget);
    });

    testWidgets('dialog has Session Name optional text field', (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('＋ New Agent Session'));
      await tester.pumpAndSettle();

      expect(find.text('Session Name (optional)'), findsOneWidget);
    });

    testWidgets('tapping Cancel in dialog closes it', (tester) async {
      await tester.pumpWidget(_buildTest());
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('＋ New Agent Session'));
      await tester.pumpAndSettle();

      expect(find.text('New Agent Session'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('New Agent Session'), findsNothing);
    });
  });

  group('WorkspaceInlineTree session labels', () {
    late WorktreeService originalService;

    setUp(() {
      originalService = WorktreeService.instance;
    });

    tearDown(() {
      WorktreeService.instance = originalService;
    });

    AgentSession worktreeSession({
      required Map<String, String> contexts,
      String? customName,
    }) {
      return AgentSession(
        id: 'sess_wt',
        type: AgentType.claude,
        workspacePath: contexts.values.first,
        workspaceId: 'ws_test',
        customName: customName,
        worktreeContexts: contexts,
      );
    }

    TerminalLoaded stateWith(AgentSession session) => TerminalLoaded(
          sessions: [session],
          activeIndex: 0,
          allSessions: [session],
        );

    testWidgets('resolves the branch name from the loaded worktrees', (tester) async {
      WorktreeService.instance = _FakeWorktreeService({
        '/fake/repo-a': [
          const WorktreeEntry(
            path: '/fake/repo-a__feat-x',
            branch: 'feat/x',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
        ],
      });
      final session = worktreeSession(
        contexts: {'/fake/repo-a': '/fake/repo-a__feat-x'},
      );

      await tester.pumpWidget(_buildTest(termState: stateWith(session)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Claude · feat/x'), findsOneWidget);
    });

    testWidgets('falls back to stripping the repo prefix when the worktree '
        'is not in the loaded list', (tester) async {
      WorktreeService.instance = _FakeWorktreeService(const {});
      final session = worktreeSession(
        contexts: {'/fake/repo-a': '/fake/repo-a__feat-x'},
      );

      await tester.pumpWidget(_buildTest(termState: stateWith(session)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Claude · feat-x'), findsOneWidget);
    });

    testWidgets('falls back to the full directory name without repo prefix', (tester) async {
      WorktreeService.instance = _FakeWorktreeService(const {});
      final session = worktreeSession(
        contexts: {'/fake/repo-a': '/elsewhere/plain_dir'},
      );

      await tester.pumpWidget(_buildTest(termState: stateWith(session)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('Claude · plain_dir'), findsOneWidget);
    });

    testWidgets('custom name wins over the worktree branch label', (tester) async {
      WorktreeService.instance = _FakeWorktreeService({
        '/fake/repo-a': [
          const WorktreeEntry(
            path: '/fake/repo-a__feat-x',
            branch: 'feat/x',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
        ],
      });
      final session = worktreeSession(
        contexts: {'/fake/repo-a': '/fake/repo-a__feat-x'},
        customName: 'My Bot',
      );

      await tester.pumpWidget(_buildTest(termState: stateWith(session)));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('My Bot'), findsOneWidget);
      expect(find.text('Claude · feat/x'), findsNothing);
    });
  });
}
