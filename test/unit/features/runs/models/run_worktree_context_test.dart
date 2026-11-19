import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/runs/data/run_bridge.dart';
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/runs/models/run_worktree_context.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';

RunConfig _config({String? workingDir}) => RunConfig(
  id: 'cfg-1',
  name: 'Build',
  command: 'make build',
  workingDir: workingDir,
);

const String _root = '/repo';
const String _wt = '/repo__feature-x';

final List<WorktreeEntry> _entries = [
  WorktreeEntry(
    path: _root,
    branch: 'main',
    commit: 'abc1234',
    isMain: true,
    isLocked: false,
    isBare: false,
  ),
  WorktreeEntry(
    path: _wt,
    branch: 'feature-x',
    commit: 'def5678',
    isMain: false,
    isLocked: false,
    isBare: false,
  ),
];

void main() {
  group('RunWorktreeContext.resolveWorkingDir', () {
    test('returns config workingDir when no worktree selected', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: '/repo/app'),
        workspacePath: '/elsewhere',
        worktreePath: null,
        worktrees: _entries,
      );
      expect(result, '/repo/app');
    });

    test('returns workspacePath when config has no workingDir', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(),
        workspacePath: _root,
        worktreePath: null,
        worktrees: _entries,
      );
      expect(result, _root);
    });

    test('applies override when config dir is the repo root', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: _root),
        workspacePath: _root,
        worktreePath: _wt,
        worktrees: _entries,
      );
      expect(result, _wt);
    });

    test('applies override when config dir is nested inside the repo', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: '/repo/packages/core'),
        workspacePath: _root,
        worktreePath: _wt,
        worktrees: _entries,
      );
      expect(result, _wt);
    });

    test('ignores override when config dir belongs to another repo', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: '/other-repo/app'),
        workspacePath: '/other-repo',
        worktreePath: _wt,
        worktrees: _entries,
      );
      expect(result, '/other-repo/app');
    });

    test('ignores override when worktree list is empty', () {
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: _root),
        workspacePath: _root,
        worktreePath: _wt,
        worktrees: const [],
      );
      expect(result, _root);
    });

    test('falls back to first entry when no entry is marked main', () {
      final entries = [
        WorktreeEntry(
          path: _root,
          branch: 'main',
          commit: 'abc1234',
          isMain: false,
          isLocked: false,
          isBare: false,
        ),
      ];
      final result = RunWorktreeContext.resolveWorkingDir(
        config: _config(workingDir: _root),
        workspacePath: _root,
        worktreePath: _wt,
        worktrees: entries,
      );
      expect(result, _wt);
    });
  });

  group('RunWorktreeContext.labelFor', () {
    test('returns root for null', () {
      expect(RunWorktreeContext.labelFor(null, _entries), 'root');
    });

    test('returns branch for a listed worktree', () {
      expect(RunWorktreeContext.labelFor(_wt, _entries), 'feature-x');
    });

    test('returns basename for an unlisted path', () {
      expect(
        RunWorktreeContext.labelFor('/tmp/gone', _entries),
        'gone',
      );
    });
  });

  group('resolveWorktreeLaunchConfig', () {
    test('returns config unchanged in a non-git directory', () async {
      final tempDir = Directory.systemTemp.createTempSync('wt_ctx_test_');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final config = _config(workingDir: tempDir.path);

      // No git repo here → WorktreeService returns [] → override ignored.
      final result = await resolveWorktreeLaunchConfig(
        config,
        '/any/worktree',
        tempDir.path,
      );
      expect(result.workingDir, tempDir.path);
      expect(identical(result, config), isTrue);
    });

    test('returns config unchanged when worktreePath is empty', () async {
      final config = _config(workingDir: _root);
      final result = await resolveWorktreeLaunchConfig(config, '', _root);
      expect(identical(result, config), isTrue);
    });
  });
}
