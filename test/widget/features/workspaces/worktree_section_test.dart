import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/workspaces/data/worktree_service.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';
import 'package:yoloit/features/workspaces/ui/worktree_section.dart';

class _FakeWorktreeService implements WorktreeService {
  Map<String, List<WorktreeEntry>> worktrees = {};
  final List<String> removed = [];
  final List<String> pruned = [];

  @override
  Future<List<WorktreeEntry>> listWorktrees(String repoPath) async =>
      worktrees[repoPath] ?? const [];

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
  }) async {
    removed.add(worktreePath);
    worktrees[repoPath] =
        worktrees[repoPath]!.where((e) => e.path != worktreePath).toList();
    return null;
  }

  @override
  Future<void> pruneWorktrees(String repoPath) async {
    pruned.add(repoPath);
  }

  @override
  Future<List<String>> listBranches(String repoPath) async => const [];
}

Widget _buildWorktreeTest(List<String> paths) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: SingleChildScrollView(
        child: WorktreeSection(
          workspacePaths: paths,
          workspaceName: 'test-ws',
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WorktreeSection widget tests', () {
    testWidgets('shows Worktrees section header and loading state', (tester) async {
      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      // Initial build: header should always be present
      expect(find.text('Worktrees'), findsOneWidget);
      // Drain all pending timers so test can complete cleanly
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('multiple paths show folder sub-headers after load', (tester) async {
      await tester.pumpWidget(
        _buildWorktreeTest(['/foo/repo-a', '/bar/repo-b']),
      );
      // Wait for async git calls to complete (will error since no real git repo)
      await tester.pump(const Duration(seconds: 3));

      // Sub-headers should be rendered (repo-a, repo-b)
      expect(find.text('repo-a'), findsOneWidget);
      expect(find.text('repo-b'), findsOneWidget);
    });

    testWidgets('multiple paths show Worktrees header once', (tester) async {
      await tester.pumpWidget(
        _buildWorktreeTest(['/foo/repo-a', '/bar/repo-b']),
      );
      await tester.pump(const Duration(seconds: 3));

      expect(find.text('Worktrees'), findsOneWidget);
    });

    testWidgets('handles errors gracefully when git fails', (tester) async {
      await tester.pumpWidget(
        _buildWorktreeTest(['/nonexistent/path-a', '/nonexistent/path-b']),
      );
      await tester.pump(const Duration(seconds: 3));

      // Section header still shown even with errors — no crash
      expect(find.text('Worktrees'), findsOneWidget);
    });

    testWidgets('single path shows Add worktree button after load', (tester) async {
      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      await tester.pump(const Duration(seconds: 3));

      // Even with git error, the "Add worktree" button appears in single-repo mode
      expect(find.text('Add worktree'), findsOneWidget);
    });
  });

  group('WorktreeSection with fake worktree data', () {
    late WorktreeService originalService;
    late _FakeWorktreeService fake;

    setUp(() {
      originalService = WorktreeService.instance;
      fake = _FakeWorktreeService();
      WorktreeService.instance = fake;
    });

    tearDown(() {
      WorktreeService.instance = originalService;
    });

    testWidgets('renders tiles with main badge, branch and commit labels', (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
          const WorktreeEntry(
            path: '/foo/repo-a__feat',
            branch: 'feat/x',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
          const WorktreeEntry(
            path: '/foo/repo-a__det',
            commit: 'abc1234',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      await tester.pump();

      expect(find.text('repo-a__feat'), findsOneWidget);
      expect(find.text('feat/x'), findsOneWidget);
      // Branch label of the detached worktree falls back to the short commit.
      expect(find.text('abc1234'), findsOneWidget);
      // 'main' appears as the first entry's branch label and as its badge.
      expect(find.text('main'), findsNWidgets(2));
      // Single-repo mode shows the outlined Add worktree button.
      expect(find.text('Add worktree'), findsOneWidget);
    });

    testWidgets('locked worktree shows lock icons', (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
          const WorktreeEntry(
            path: '/foo/repo-a__locked',
            branch: 'feat/locked',
            isMain: false,
            isLocked: true,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      await tester.pump();

      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsOneWidget);
    });

    testWidgets('multi-repo shows headers, inline add buttons and divider', (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
        ],
        '/bar/repo-b': [
          const WorktreeEntry(
            path: '/bar/repo-b',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a', '/bar/repo-b']));
      await tester.pump();

      // Each name appears twice: per-repo header + main worktree tile.
      expect(find.text('repo-a'), findsNWidgets(2));
      expect(find.text('repo-b'), findsNWidgets(2));
      // Inline "Add worktree" row per repo with worktrees.
      expect(find.text('Add worktree'), findsNWidgets(2));
      expect(find.byType(Divider), findsOneWidget);
      // Per-repo prune buttons in multi-repo mode.
      expect(find.byIcon(Icons.cleaning_services_outlined), findsNWidgets(2));
    });

    testWidgets('prune button calls the service and reloads', (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
        ],
        '/bar/repo-b': [
          const WorktreeEntry(
            path: '/bar/repo-b',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a', '/bar/repo-b']));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.cleaning_services_outlined).first);
      await tester.pump();

      expect(fake.pruned, ['/foo/repo-a']);
    });

    testWidgets('hovering a non-main tile reveals remove; confirming removes it',
        (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
          const WorktreeEntry(
            path: '/foo/repo-a__wt1',
            branch: 'feat/one',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(
        location: tester.getCenter(find.text('repo-a__wt1')),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.text('Remove Worktree'), findsOneWidget);

      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(fake.removed, ['/foo/repo-a__wt1']);
      expect(find.text('repo-a__wt1'), findsNothing);
    });

    testWidgets('cancelling the remove dialog keeps the worktree', (tester) async {
      fake.worktrees = {
        '/foo/repo-a': [
          const WorktreeEntry(
            path: '/foo/repo-a',
            branch: 'main',
            isMain: true,
            isLocked: false,
            isBare: false,
          ),
          const WorktreeEntry(
            path: '/foo/repo-a__wt1',
            branch: 'feat/one',
            isMain: false,
            isLocked: false,
            isBare: false,
          ),
        ],
      };

      await tester.pumpWidget(_buildWorktreeTest(['/foo/repo-a']));
      await tester.pump();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(gesture.removePointer);
      await gesture.addPointer(
        location: tester.getCenter(find.text('repo-a__wt1')),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Remove Worktree'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(fake.removed, isEmpty);
      expect(find.text('repo-a__wt1'), findsOneWidget);
    });
  });
}

