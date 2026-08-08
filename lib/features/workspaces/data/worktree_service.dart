import 'package:flutter/foundation.dart';
import 'package:process_run/process_run.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';

class WorktreeService {
  const WorktreeService._();

  /// Singleton. Mutable so widget tests can substitute a mock without
  /// spawning real `git` processes.
  @visibleForTesting
  static WorktreeService instance = const WorktreeService._();

  Future<List<WorktreeEntry>> listWorktrees(String repoPath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['worktree', 'list', '--porcelain'],
        workingDirectory: repoPath,
      );
      return _parseWorktrees(result.stdout.toString());
    } catch (_) {
      return [];
    }
  }

  Future<String?> addWorktree(
    String repoPath,
    String worktreePath,
    String branchOrCommit, {
    bool createNewBranch = false,
  }) async {
    try {
      final args = ['worktree', 'add'];
      if (createNewBranch) {
        args.addAll(['-b', branchOrCommit, worktreePath]);
      } else {
        args.addAll([worktreePath, branchOrCommit]);
      }
      final result = await runExecutableArguments(
        'git',
        args,
        workingDirectory: repoPath,
      );
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        return err.isNotEmpty ? err : 'git worktree add failed (exit ${result.exitCode})';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<String?> removeWorktree(
    String repoPath,
    String worktreePath, {
    bool force = false,
  }) async {
    try {
      final args = ['worktree', 'remove', if (force) '--force', worktreePath];
      final result = await runExecutableArguments(
        'git',
        args,
        workingDirectory: repoPath,
      );
      if (result.exitCode != 0) {
        final err = result.stderr.toString().trim();
        return err.isNotEmpty ? err : 'git worktree remove failed (exit ${result.exitCode})';
      }
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> pruneWorktrees(String repoPath) async {
    try {
      await runExecutableArguments(
        'git',
        ['worktree', 'prune'],
        workingDirectory: repoPath,
      );
    } catch (_) {}
  }

  Future<List<String>> listBranches(String repoPath) async {
    try {
      final result = await runExecutableArguments(
        'git',
        ['branch', '--list', '--format=%(refname:short)'],
        workingDirectory: repoPath,
      );
      return result.stdout
          .toString()
          .split('\n')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<WorktreeEntry> _parseWorktrees(String output) {
    if (output.trim().isEmpty) return [];

    final blocks = output.split(RegExp(r'\n\n+'));
    bool isFirst = true;
    final entries = <WorktreeEntry>[];

    for (final block in blocks) {
      final lines = block.trim().split('\n');
      if (lines.isEmpty || lines.first.trim().isEmpty) continue;

      String? path;
      String? commit;
      String? branch;
      bool isLocked = false;
      bool isBare = false;
      bool isDetached = false;

      for (final line in lines) {
        if (line.startsWith('worktree ')) {
          path = line.substring('worktree '.length).trim();
        } else if (line.startsWith('HEAD ')) {
          commit = line.substring('HEAD '.length).trim();
          if (commit.length > 7) commit = commit.substring(0, 7);
        } else if (line.startsWith('branch ')) {
          final ref = line.substring('branch '.length).trim();
          branch = ref.replaceFirst('refs/heads/', '');
        } else if (line == 'detached') {
          isDetached = true;
        } else if (line == 'bare') {
          isBare = true;
        } else if (line.startsWith('locked')) {
          isLocked = true;
        }
      }

      if (path == null) continue;
      if (isDetached) branch = null;

      entries.add(WorktreeEntry(
        path: path,
        branch: branch,
        commit: commit,
        isMain: isFirst,
        isLocked: isLocked,
        isBare: isBare,
      ));
      isFirst = false;
    }

    return entries;
  }
}
