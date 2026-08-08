import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';

class AgentWorkspaceDirService {
  AgentWorkspaceDirService._();
  static final instance = AgentWorkspaceDirService._();

  static String _baseDir() =>
      p.join(PlatformDirs.instance.configDir, 'workspaces');

  String dirForAgent(String workspaceId, String agentId) =>
      p.join(_baseDir(), workspaceId, 'agents', agentId);

  /// Creates the agent directory with symlinks for each repo → selected worktree path.
  /// [worktreeContexts] maps repoPath → selectedWorktreePath.
  /// Returns the agent directory path.
  Future<String> createAgentDir(
    String workspaceId,
    String agentId,
    Map<String, String> worktreeContexts,
  ) async {
    final dir = Directory(dirForAgent(workspaceId, agentId));
    await dir.create(recursive: true);

    for (final entry in worktreeContexts.entries) {
      final repoPath = entry.key;
      final worktreePath = entry.value;
      final linkName = p.basename(repoPath);
      final link = Link(p.join(dir.path, linkName));
      if (await link.exists()) await link.delete();
      await link.create(worktreePath);
    }

    return dir.path;
  }

  Future<void> deleteAgentDir(String workspaceId, String agentId) async {
    final dir = Directory(dirForAgent(workspaceId, agentId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Reconstructs worktreeContexts by inspecting symlinks in the agent dir.
  /// Used to recover context after app restart when it wasn't persisted.
  /// Returns null if no worktree symlinks are found.
  Future<Map<String, String>?> readWorktreeContexts(
    String workspaceId,
    String agentId,
    List<String> workspacePaths,
  ) async {
    final dir = Directory(dirForAgent(workspaceId, agentId));
    if (!await dir.exists()) return null;

    final result = <String, String>{};
    // followLinks: false — worktree entries are symlinks; following them
    // would list valid ones as Directory and hide them from the scan.
    for (final entity in await dir.list(followLinks: false).toList()) {
      if (entity is Link) {
        final String target;
        try {
          target = await entity.resolveSymbolicLinks();
        } on FileSystemException {
          continue; // Dangling symlink — nothing to recover.
        }
        // Find the original workspace path whose basename matches the link name.
        final linkName = p.basename(entity.path);
        final originalPath = workspacePaths
            .where((wp) => p.basename(wp) == linkName)
            .firstOrNull;
        if (originalPath != null && target != originalPath) {
          // Symlink points somewhere different → it's a worktree.
          if (Directory(target).existsSync()) {
            result[originalPath] = target;
          }
        }
      }
    }
    return result.isEmpty ? null : result;
  }
}
