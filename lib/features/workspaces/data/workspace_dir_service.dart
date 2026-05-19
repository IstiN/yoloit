import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/skills/data/skills_install_service.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Manages the internal workspace directory structure.
///
/// Each workspace gets a directory at:
///   `~/.config/yoloit/workspaces/{workspace-id}/`
///
/// Inside it, each referenced folder is represented as a symlink:
///   `~/.config/yoloit/workspaces/{id}/repo-name -> /actual/path/to/repo`
///
/// Copilot and Claude are launched with this directory as their working dir,
/// so they can "see" all referenced repositories simultaneously.
class WorkspaceDirService {
  WorkspaceDirService._();
  static final instance = WorkspaceDirService._();

  static String _baseDir() =>
      p.join(PlatformDirs.instance.configDir, 'workspaces');

  String dirForWorkspace(String workspaceId) =>
      p.join(_baseDir(), workspaceId);

  /// Creates the workspace directory and syncs symlinks to match [paths].
  /// Old symlinks to removed paths are deleted; new ones are created.
  Future<void> syncSymlinks(Workspace workspace) async {
    final dir = Directory(workspace.workspaceDir);
    await dir.create(recursive: true);

    // Build desired symlink targets keyed by link name.
    final desired = <String, String>{};
    for (final path in workspace.paths) {
      final linkName = _uniqueLinkName(p.basename(path), desired.keys.toSet());
      desired[linkName] = path;
    }

    // Remove stale symlinks (links whose target is no longer in paths).
    final existing = await dir.list(followLinks: false).toList();
    for (final entity in existing) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type != FileSystemEntityType.link) continue;
      final target = await Link(entity.path).target();
      final isDesired =
          desired.values.any((d) => p.equals(d, target) || d == target);
      if (!isDesired) await Link(entity.path).delete();
    }

    // Create missing symlinks.
    for (final entry in desired.entries) {
      final linkPath = p.join(workspace.workspaceDir, entry.key);
      final link = Link(linkPath);
      if (!await link.exists()) {
        await link.create(entry.value);
      }
    }
  }

  /// Deletes the workspace directory (called when workspace is removed).
  Future<void> deleteDir(String workspaceId) async {
    final dir = Directory(p.join(_baseDir(), workspaceId));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Syncs skill symlinks for the workspace based on its enabledSkills list.
  /// Delegates to SkillsInstallService which handles both Claude and Copilot patterns.
  Future<void> syncSkillSymlinks(Workspace workspace) async {
    await SkillsInstallService.instance.syncWorkspaceSkills(workspace);
  }

  /// Ensures link name is unique by appending _2, _3 etc. if needed.
  static String _uniqueLinkName(String base, Set<String> existing) {
    if (!existing.contains(base)) return base;
    var i = 2;
    while (existing.contains('${base}_$i')) {
      i++;
    }
    return '${base}_$i';
  }
}
