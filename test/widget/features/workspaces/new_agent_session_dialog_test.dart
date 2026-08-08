import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/new_agent_session_dialog.dart';

class _MockTerminalCubit extends Mock implements TerminalCubit {}

class _MockWorktreeService extends Mock implements WorktreeService {}

const _repoPath = '/repo/main';

WorktreeEntry _entry(String path, String? branch, {bool isMain = false}) {
  return WorktreeEntry(
    path: path,
    branch: branch,
    commit: 'abc1234',
    isMain: isMain,
    isLocked: false,
    isBare: false,
  );
}

_MockTerminalCubit _stubTerminalCubit() {
  final cubit = _MockTerminalCubit();
  when(() => cubit.state).thenReturn(
    const TerminalLoaded(sessions: [], activeIndex: 0),
  );
  when(
    () => cubit.stream,
  ).thenAnswer((_) => const Stream<TerminalState>.empty());
  when(
    () => cubit.spawnSession(
      type: any(named: 'type'),
      workspacePath: any(named: 'workspacePath'),
      workspaceId: any(named: 'workspaceId'),
      savedSessionId: any(named: 'savedSessionId'),
      worktreeContexts: any(named: 'worktreeContexts'),
      enabledSkills: any(named: 'enabledSkills'),
    ),
  ).thenAnswer((_) async {});
  return cubit;
}

Widget _buildHost({
  required TerminalCubit terminalCubit,
  required Workspace workspace,
  required Map<String, List<WorktreeEntry>> worktrees,
  VoidCallback? onSpawned,
}) {
  return BlocProvider<TerminalCubit>.value(
    value: terminalCubit,
    child: MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: Builder(
          builder:
              (context) => Center(
                child: ElevatedButton(
                  onPressed:
                      () => showNewAgentSessionDialog(
                        context,
                        workspace: workspace,
                        worktrees: worktrees,
                        onSpawned: onSpawned,
                      ),
                  child: const Text('open'),
                ),
              ),
        ),
      ),
    ),
  );
}

/// Opens the dialog and waits for the async branch listing to land.
Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump();
  expect(find.text('New Agent Session'), findsOneWidget);
}

/// The repo branch-picker field, identified by its hint.
Finder _branchPickerField() => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.hintText == 'Search or create branch…',
);

/// The optional session-name field, identified by its hint.
Finder _nameField() => find.byWidgetPredicate(
  (w) =>
      w is TextField &&
      w.decoration?.hintText == 'Leave empty to use agent name',
);

Finder _startButton() => find.widgetWithText(ElevatedButton, 'Start');

/// Selects [branch] through the picker's keyboard submit (exact match →
/// existing branch). Overlay rows are floated via CompositedTransformFollower
/// and are not reliably hittable in widget tests.
Future<void> _submitBranch(WidgetTester tester, String branch) async {
  await tester.enterText(_branchPickerField(), branch);
  await tester.pump(const Duration(milliseconds: 200)); // search debounce
  await tester.testTextInput.receiveAction(TextInputAction.done);
  await tester.pump();
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late WorktreeService originalService;
  late _MockWorktreeService worktreeService;

  const workspace = Workspace(
    id: 'ws_1',
    name: 'alpha',
    paths: [_repoPath],
    enabledSkills: ['skill_a'],
  );

  setUpAll(() {
    registerFallbackValue(AgentType.terminal);
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    originalService = WorktreeService.instance;
    worktreeService = _MockWorktreeService();
    WorktreeService.instance = worktreeService;
    when(
      () => worktreeService.listBranches(any()),
    ).thenAnswer((_) async => ['main', 'feature', 'develop']);
    when(
      () => worktreeService.addWorktree(
        any(),
        any(),
        any(),
        createNewBranch: any(named: 'createNewBranch'),
      ),
    ).thenAnswer((_) async => null);
  });

  tearDown(() {
    WorktreeService.instance = originalService;
  });

  group('branch picker rendering', () {
    testWidgets('shows repo picker and branch rows from the listing', (
      tester,
    ) async {
      final worktrees = {
        _repoPath: [
          _entry(_repoPath, 'main', isMain: true),
          _entry('/repo/main__feature', 'feature'),
        ],
      };
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: _stubTerminalCubit(),
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      // Repo section with the current (checked-out) branch preselected.
      expect(find.text('main'), findsWidgets);
      // The autofocus picker opens its overlay: all branches listed.
      expect(find.text('feature'), findsWidgets);
      expect(find.text('develop'), findsOneWidget);
    });

    testWidgets('repo with empty worktree list renders no picker', (
      tester,
    ) async {
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: _stubTerminalCubit(),
          workspace: workspace,
          worktrees: const {_repoPath: []},
        ),
      );
      await _openDialog(tester);

      expect(find.text('New Agent Session'), findsOneWidget);
      expect(_branchPickerField(), findsNothing);
    });
  });

  group('confirm flow', () {
    testWidgets('confirm with default branch spawns without worktree contexts', (
      tester,
    ) async {
      var spawned = false;
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {_repoPath: [_entry(_repoPath, 'main', isMain: true)]};
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
          onSpawned: () => spawned = true,
        ),
      );
      await _openDialog(tester);

      // Give the session a custom name.
      await tester.enterText(_nameField(), 'My Session');
      await tester.tap(_startButton());
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => terminalCubit.spawnSession(
          type: AgentType.copilot,
          workspacePath: workspace.workspaceDir,
          workspaceId: 'ws_1',
          savedSessionId: captureAny(named: 'savedSessionId'),
          worktreeContexts: captureAny(named: 'worktreeContexts'),
          enabledSkills: ['skill_a'],
        ),
      ).captured;
      expect(captured[0] as String, startsWith('copilot_'));
      // Main checkout selected → no agent worktree contexts needed.
      expect(captured[1], isNull);
      verify(() => terminalCubit.renameSession(any(), 'My Session')).called(1);
      expect(spawned, isTrue);
      expect(find.text('New Agent Session'), findsNothing);
    });

    testWidgets('selecting an existing worktree branch resolves its path', (
      tester,
    ) async {
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {
        _repoPath: [
          _entry(_repoPath, 'main', isMain: true),
          _entry('/repo/main__feature', 'feature'),
        ],
      };
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      await _submitBranch(tester, 'feature');
      await tester.tap(_startButton());
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => terminalCubit.spawnSession(
          type: any(named: 'type'),
          workspacePath: any(named: 'workspacePath'),
          workspaceId: any(named: 'workspaceId'),
          savedSessionId: any(named: 'savedSessionId'),
          worktreeContexts: captureAny(named: 'worktreeContexts'),
          enabledSkills: any(named: 'enabledSkills'),
        ),
      ).captured;
      expect(captured.single, {_repoPath: '/repo/main__feature'});
      // Already checked out → no worktree creation needed.
      verifyNever(
        () => worktreeService.addWorktree(
          any(),
          any(),
          any(),
          createNewBranch: any(named: 'createNewBranch'),
        ),
      );
    });

    testWidgets('selecting a plain branch creates its worktree on confirm', (
      tester,
    ) async {
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {_repoPath: [_entry(_repoPath, 'main', isMain: true)]};
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      await _submitBranch(tester, 'develop');
      await tester.tap(_startButton());
      await tester.pump();
      await tester.pump();

      verify(
        () => worktreeService.addWorktree(
          _repoPath,
          '/repo/main__develop',
          'develop',
          createNewBranch: false,
        ),
      ).called(1);
      final captured = verify(
        () => terminalCubit.spawnSession(
          type: any(named: 'type'),
          workspacePath: any(named: 'workspacePath'),
          workspaceId: any(named: 'workspaceId'),
          savedSessionId: any(named: 'savedSessionId'),
          worktreeContexts: captureAny(named: 'worktreeContexts'),
          enabledSkills: any(named: 'enabledSkills'),
        ),
      ).captured;
      expect(captured.single, {_repoPath: '/repo/main__develop'});
    });

    testWidgets('worktree creation failure blocks the spawn and shows error', (
      tester,
    ) async {
      when(
        () => worktreeService.addWorktree(
          any(),
          any(),
          any(),
          createNewBranch: any(named: 'createNewBranch'),
        ),
      ).thenAnswer((_) async => 'fatal: already exists');
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {_repoPath: [_entry(_repoPath, 'main', isMain: true)]};
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      await _submitBranch(tester, 'develop');
      await tester.tap(_startButton());
      await tester.pump();
      await tester.pump();

      expect(find.text('fatal: already exists'), findsOneWidget);
      verifyNever(
        () => terminalCubit.spawnSession(
          type: any(named: 'type'),
          workspacePath: any(named: 'workspacePath'),
          workspaceId: any(named: 'workspaceId'),
          savedSessionId: any(named: 'savedSessionId'),
          worktreeContexts: any(named: 'worktreeContexts'),
          enabledSkills: any(named: 'enabledSkills'),
        ),
      );
      // Dialog stays open so the user can fix the selection.
      expect(find.text('New Agent Session'), findsOneWidget);
    });

    testWidgets('typing a new branch name creates branch and worktree eagerly', (
      tester,
    ) async {
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {_repoPath: [_entry(_repoPath, 'main', isMain: true)]};
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      await tester.enterText(_branchPickerField(), 'brand-new');
      await tester.pump(const Duration(milliseconds: 200)); // search debounce
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump();

      verify(
        () => worktreeService.addWorktree(
          _repoPath,
          '/repo/main__brand-new',
          'brand-new',
          createNewBranch: true,
        ),
      ).called(1);

      await tester.tap(_startButton());
      await tester.pump();
      await tester.pump();

      final captured = verify(
        () => terminalCubit.spawnSession(
          type: any(named: 'type'),
          workspacePath: any(named: 'workspacePath'),
          workspaceId: any(named: 'workspaceId'),
          savedSessionId: any(named: 'savedSessionId'),
          worktreeContexts: captureAny(named: 'worktreeContexts'),
          enabledSkills: any(named: 'enabledSkills'),
        ),
      ).captured;
      expect(captured.single, {_repoPath: '/repo/main__brand-new'});
    });

    testWidgets('cancel closes the dialog without spawning', (tester) async {
      final terminalCubit = _stubTerminalCubit();
      final worktrees = {_repoPath: [_entry(_repoPath, 'main', isMain: true)]};
      await tester.pumpWidget(
        _buildHost(
          terminalCubit: terminalCubit,
          workspace: workspace,
          worktrees: worktrees,
        ),
      );
      await _openDialog(tester);

      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.pump();

      expect(find.text('New Agent Session'), findsNothing);
      verifyNever(
        () => terminalCubit.spawnSession(
          type: any(named: 'type'),
          workspacePath: any(named: 'workspacePath'),
          workspaceId: any(named: 'workspaceId'),
        ),
      );
    });
  });
}
