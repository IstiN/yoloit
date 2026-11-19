import 'package:path/path.dart' as p;
import 'package:yoloit/features/runs/models/run_config.dart';
import 'package:yoloit/features/workspaces/models/worktree_model.dart';

/// Pure logic for launching a run config from a selected git worktree.
///
/// The user picks a worktree (or the repo root) in the Run Configs panel;
/// only the working directory changes for the spawned session — command,
/// env and everything else stay exactly as configured.
abstract final class RunWorktreeContext {
  /// Resolves the working directory to spawn [config] in.
  ///
  /// Returns [worktreePath] only when a worktree is selected AND the
  /// config's own directory belongs to the same repository (i.e. it is the
  /// main worktree root or nested inside it) — otherwise the override is
  /// ignored and the config runs from its normal directory. This keeps
  /// configs pointing at other repos unaffected by the panel selection.
  static String resolveWorkingDir({
    required RunConfig config,
    required String workspacePath,
    required String? worktreePath,
    required List<WorktreeEntry> worktrees,
  }) {
    final base = config.workingDir ?? workspacePath;
    if (worktreePath == null || worktrees.isEmpty) return base;
    final main = worktrees.firstWhere(
      (w) => w.isMain,
      orElse: () => worktrees.first,
    );
    final root = p.normalize(main.path);
    final candidate = p.normalize(base);
    final inside = candidate == root || p.isWithin(root, candidate);
    return inside ? worktreePath : base;
  }

  /// Short display label for a worktree path within [worktrees]; falls back
  /// to the directory name for paths that are not listed (e.g. stale panel
  /// state after a worktree was removed).
  static String labelFor(String? worktreePath, List<WorktreeEntry> worktrees) {
    if (worktreePath == null) return 'root';
    for (final w in worktrees) {
      if (p.normalize(w.path) == p.normalize(worktreePath)) {
        return w.branch ?? p.basename(w.path);
      }
    }
    return p.basename(worktreePath);
  }
}
