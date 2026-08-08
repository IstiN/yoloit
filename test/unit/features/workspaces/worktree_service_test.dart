import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/workspaces/data/worktree_service.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Creates a minimal git repo with one empty commit in [dir].
Future<void> _initGitRepo(Directory dir) async {
  Future<void> run(List<String> args) async {
    final result = await Process.run('git', args, workingDirectory: dir.path);
    if (result.exitCode != 0) {
      throw Exception('git ${args.join(' ')} failed: ${result.stderr}');
    }
  }

  await run(['init']);
  await run(['config', 'user.email', 'test@test.com']);
  await run(['config', 'user.name', 'Test User']);
  await run(['commit', '--allow-empty', '-m', 'init']);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final service = WorktreeService.instance;
  const nonExistentPath = '/nonexistent/path/that/does/not/exist';

  group('WorktreeService — non-existent paths', () {
    test('listWorktrees returns empty list for non-existent path without throwing', () async {
      final result = await service.listWorktrees(nonExistentPath);
      expect(result, isEmpty);
    });

    test('listBranches returns empty list for non-existent path without throwing', () async {
      final result = await service.listBranches(nonExistentPath);
      expect(result, isEmpty);
    });

    test('addWorktree returns error string for non-existent path', () async {
      final result = await service.addWorktree(
        nonExistentPath,
        '/some/worktree/path',
        'feature-branch',
        createNewBranch: true,
      );
      expect(result, isNotNull);
      expect(result, isA<String>());
      expect(result!.isNotEmpty, isTrue);
    });

    test('removeWorktree returns error string for non-existent path', () async {
      final result = await service.removeWorktree(
        nonExistentPath,
        '/some/worktree/path',
      );
      expect(result, isNotNull);
      expect(result, isA<String>());
      expect(result!.isNotEmpty, isTrue);
    });

    test('pruneWorktrees completes without error for non-existent path', () async {
      await expectLater(
        service.pruneWorktrees(nonExistentPath),
        completes,
      );
    });
  });

  group('WorktreeService — addWorktree error message variants', () {
    test('addWorktree without createNewBranch also returns error for non-existent path', () async {
      final result = await service.addWorktree(
        nonExistentPath,
        '/some/worktree/path',
        'existing-branch',
        createNewBranch: false,
      );
      expect(result, isNotNull);
      expect(result!.isNotEmpty, isTrue);
    });

    test('removeWorktree with force flag returns error for non-existent path', () async {
      final result = await service.removeWorktree(
        nonExistentPath,
        '/some/worktree/path',
        force: true,
      );
      expect(result, isNotNull);
      expect(result!.isNotEmpty, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // Parsing tests via a real git repo in a temp directory
  // -------------------------------------------------------------------------

  group('WorktreeService — parsing via real git repo', () {
    late Directory repoDir;

    setUp(() async {
      repoDir = await Directory.systemTemp.createTemp('wt_parse_test_');
      await _initGitRepo(repoDir);
    });

    tearDown(() async {
      // Remove any linked worktrees first, then the main repo.
      await service.pruneWorktrees(repoDir.path);
      if (await repoDir.exists()) await repoDir.delete(recursive: true);
    });

    test('listWorktrees returns one entry for a repo with no extra worktrees', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries, hasLength(1));
    });

    test('main worktree entry has isMain = true', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries.first.isMain, isTrue);
    });

    test('main worktree path matches the repo directory', () async {
      final entries = await service.listWorktrees(repoDir.path);
      // macOS resolves symlinks so compare basenames.
      expect(p.basename(entries.first.path), p.basename(repoDir.path));
    });

    test('main worktree branch is the default branch (main or master)', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries.first.branch, isNotNull);
      expect(entries.first.branch, isIn(['main', 'master']));
    });

    test('main worktree commit is a 7-char short SHA', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries.first.commit, isNotNull);
      expect(entries.first.commit!.length, 7);
    });

    test('main worktree isLocked is false', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries.first.isLocked, isFalse);
    });

    test('main worktree isBare is false', () async {
      final entries = await service.listWorktrees(repoDir.path);
      expect(entries.first.isBare, isFalse);
    });

    test('addWorktree creates a new branch worktree entry', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__feat'));
      try {
        await service.addWorktree(
          repoDir.path,
          wtDir.path,
          'feature/auth',
          createNewBranch: true,
        );
        final entries = await service.listWorktrees(repoDir.path);
        expect(entries, hasLength(2));
      } finally {
        if (await wtDir.exists()) await wtDir.delete(recursive: true);
      }
    });

    test('linked worktree has isMain = false', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__feat2'));
      try {
        await service.addWorktree(
          repoDir.path,
          wtDir.path,
          'feature/b',
          createNewBranch: true,
        );
        final entries = await service.listWorktrees(repoDir.path);
        final linked = entries.firstWhere((e) => !e.isMain);
        expect(linked.isMain, isFalse);
      } finally {
        if (await wtDir.exists()) await wtDir.delete(recursive: true);
      }
    });

    test('linked worktree branch name is parsed without refs/heads/ prefix', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__feat3'));
      try {
        await service.addWorktree(
          repoDir.path,
          wtDir.path,
          'feature/login',
          createNewBranch: true,
        );
        final entries = await service.listWorktrees(repoDir.path);
        final linked = entries.firstWhere((e) => !e.isMain);
        expect(linked.branch, 'feature/login');
        expect(linked.branch, isNot(contains('refs/heads/')));
      } finally {
        if (await wtDir.exists()) await wtDir.delete(recursive: true);
      }
    });

    test('locked worktree has isLocked = true', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__lock'));
      try {
        await service.addWorktree(
          repoDir.path,
          wtDir.path,
          'feature/lock-test',
          createNewBranch: true,
        );
        await Process.run('git', ['worktree', 'lock', wtDir.path],
            workingDirectory: repoDir.path);

        final entries = await service.listWorktrees(repoDir.path);
        final locked = entries.firstWhere((e) => !e.isMain);
        expect(locked.isLocked, isTrue);
      } finally {
        // Unlock before removal so git can clean it up.
        await Process.run('git', ['worktree', 'unlock', wtDir.path],
            workingDirectory: repoDir.path);
        if (await wtDir.exists()) await wtDir.delete(recursive: true);
      }
    });

    test('listBranches returns at least the default branch', () async {
      final branches = await service.listBranches(repoDir.path);
      expect(branches, isNotEmpty);
      expect(branches, anyElement(isIn(['main', 'master'])));
    });

    test('listBranches includes newly created branch after addWorktree', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__br'));
      try {
        await service.addWorktree(
          repoDir.path,
          wtDir.path,
          'feature/new-branch',
          createNewBranch: true,
        );
        final branches = await service.listBranches(repoDir.path);
        expect(branches, contains('feature/new-branch'));
      } finally {
        if (await wtDir.exists()) await wtDir.delete(recursive: true);
      }
    });

    test('removeWorktree returns null on success and worktree is gone', () async {
      final wtDir = Directory(p.join(repoDir.parent.path, '${p.basename(repoDir.path)}__rem'));
      await service.addWorktree(
        repoDir.path,
        wtDir.path,
        'feature/remove-me',
        createNewBranch: true,
      );
      expect(await wtDir.exists(), isTrue);

      final err = await service.removeWorktree(repoDir.path, wtDir.path);
      expect(err, isNull);
      expect(await wtDir.exists(), isFalse);

      final entries = await service.listWorktrees(repoDir.path);
      expect(entries, hasLength(1)); // only main remains
    });
  });
}
