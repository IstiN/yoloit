import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

/// Handles skill installation and workspace skill symlink management.
///
/// Install destinations:
///   Global store:      ~/.config/yoloit/skills/{skill-id}/
///   Claude pattern:    {workspaceDir}/.agents/skills/{skill-id} -> global store
///   Copilot pattern:   {workspaceDir}/.github/copilot/{skill-id} -> global store
///   Repo install:      {repoPath}/.agents/skills/{skill-id}/  (copy)
class SkillsInstallService {
  SkillsInstallService._();
  static final instance = SkillsInstallService._();

  String get _skillsDir => PlatformDirs.instance.skillsDir;

  String _claudeSkillsPath(String workspaceDir) =>
      p.join(workspaceDir, '.claude', 'commands');

  String _copilotSkillsPath(String workspaceDir) =>
      p.join(workspaceDir, '.github', 'copilot');

  String _cursorSkillsPath(String workspaceDir) =>
      p.join(workspaceDir, '.cursor', 'rules');

  String _windsurfSkillsPath(String workspaceDir) =>
      p.join(workspaceDir, '.windsurf', 'rules');

  String _geminiSkillsPath(String workspaceDir) =>
      p.join(workspaceDir, '.gemini', 'skills');

  // ── Install ─────────────────────────────────────────────────────────────────

  /// Installs a GitHub-sourced skill into the global skills dir.
  ///
  /// For flutter/skills: downloads the skill via gh CLI if available,
  /// otherwise clones the skill subdirectory.
  Future<SkillInstallResult> installGithubSkill(SkillEntry skill) async {
    final dest = Directory(p.join(_skillsDir, skill.id));
    if (await dest.exists()) {
      return SkillInstallResult.alreadyInstalled(skill.id);
    }

    // Try gh CLI first (fastest), fall back to git sparse checkout.
    final ghResult = await _tryGhDownload(skill);
    if (ghResult != null) return ghResult;

    return SkillInstallResult.error(
      skill.id,
      'Could not install skill. Ensure "gh" (GitHub CLI) is installed.\n'
      'Manual: gh skill install ${skill.id} or clone from ${skill.source}',
    );
  }

  Future<SkillInstallResult?> _tryGhDownload(SkillEntry skill) async {
    // Use gh api to download the skill folder from github
    // flutter/skills stores each skill as a directory with SKILL.md
    final parts = skill.source.split('/');
    if (parts.length < 2) return null;

    final owner = parts[0];
    final repo = parts[1];

    try {
      await Directory(_skillsDir).create(recursive: true);
      // Use git sparse-checkout to get just the skill folder
      final result = await Process.run('git', [
        'clone',
        '--depth=1',
        '--filter=blob:none',
        '--sparse',
        'https://github.com/$owner/$repo.git',
        p.join(_skillsDir, '_tmp_${skill.id}'),
      ]);
      if (result.exitCode != 0) return null;

      final tmpDir = Directory(p.join(_skillsDir, '_tmp_${skill.id}'));
      await Process.run('git', ['sparse-checkout', 'set', skill.id],
          workingDirectory: tmpDir.path);
      await Process.run('git', ['checkout'], workingDirectory: tmpDir.path);

      final srcSkillDir = Directory(p.join(tmpDir.path, skill.id));
      if (await srcSkillDir.exists()) {
        await _copyDirectory(srcSkillDir, Directory(p.join(_skillsDir, skill.id)));
      } else {
        // Some repos store skills at root level as SKILL.md
        final skillMd = File(p.join(tmpDir.path, 'SKILL.md'));
        if (await skillMd.exists()) {
          final dest = await Directory(p.join(_skillsDir, skill.id)).create(recursive: true);
          await skillMd.copy(p.join(dest.path, 'SKILL.md'));
        }
      }
      await tmpDir.delete(recursive: true);
      return SkillInstallResult.success(skill.id);
    } catch (e) {
      // Clean up tmp on error
      final tmpDir = Directory(p.join(_skillsDir, '_tmp_${skill.id}'));
      if (await tmpDir.exists()) await tmpDir.delete(recursive: true);
      return null;
    }
  }

  /// Runs an install script for script-based skills.
  /// Executes the command in a subprocess inside the global skills dir so the
  /// skill ends up installed at ~/.config/yoloit/skills/{skill-id}/.
  Future<SkillInstallResult> runInstallScript(SkillEntry skill) async {
    final command = skill.installCommand ?? '';
    if (command.isEmpty) {
      return SkillInstallResult.error(skill.id, 'No install command specified');
    }

    final skillDir = Directory(p.join(_skillsDir, skill.id));
    await skillDir.create(recursive: true);

    try {
      final result = await Process.run(
        'bash',
        ['-c', command],
        workingDirectory: skillDir.path,
        environment: {
          ...Platform.environment,
          'SKILLS_DIR': skillDir.path,
          'SKILL_ID': skill.id,
        },
        runInShell: false,
      );

      if (result.exitCode != 0) {
        // Clean up empty dir on failure
        if (await skillDir.list().isEmpty) await skillDir.delete();
        return SkillInstallResult.error(
          skill.id,
          'Install script failed (exit ${result.exitCode}):\n${result.stderr}',
        );
      }

      // Ensure a SKILL.md exists so the skill shows up in the store.
      final skillMd = File(p.join(skillDir.path, 'SKILL.md'));
      if (!await skillMd.exists()) {
        await skillMd.writeAsString('# ${skill.name}\n\n${skill.description}\n');
      }

      return SkillInstallResult.success(skill.id);
    } catch (e) {
      if (await skillDir.list().isEmpty) {
        try { await skillDir.delete(); } catch (_) {}
      }
      return SkillInstallResult.error(skill.id, 'Failed to run install script: $e');
    }
  }

  // ── Workspace symlink management ────────────────────────────────────────────

  /// Syncs skill symlinks for a workspace based on its enabledSkills list.
  /// Creates/removes symlinks for all supported AI providers.
  Future<void> syncWorkspaceSkills(Workspace workspace) async {
    await _syncSkillLinks(
      skillsDir: _claudeSkillsPath(workspace.workspaceDir),
      enabledSkillIds: workspace.enabledSkills,
      globalSkillsDir: _skillsDir,
    );

    await _syncSkillLinks(
      skillsDir: _copilotSkillsPath(workspace.workspaceDir),
      enabledSkillIds: workspace.enabledSkills,
      globalSkillsDir: _skillsDir,
      linkStyle: _LinkStyle.copilot,
    );

    await _syncSkillLinks(
      skillsDir: _cursorSkillsPath(workspace.workspaceDir),
      enabledSkillIds: workspace.enabledSkills,
      globalSkillsDir: _skillsDir,
    );

    await _syncSkillLinks(
      skillsDir: _windsurfSkillsPath(workspace.workspaceDir),
      enabledSkillIds: workspace.enabledSkills,
      globalSkillsDir: _skillsDir,
    );

    await _syncSkillLinks(
      skillsDir: _geminiSkillsPath(workspace.workspaceDir),
      enabledSkillIds: workspace.enabledSkills,
      globalSkillsDir: _skillsDir,
    );
  }

  /// Syncs skill symlinks into an agent session directory.
  Future<void> syncSessionSkills({
    required String sessionDir,
    required List<String> enabledSkillIds,
  }) async {
    for (final skillsDir in [
      p.join(sessionDir, '.claude', 'commands'),
      p.join(sessionDir, '.cursor', 'rules'),
      p.join(sessionDir, '.windsurf', 'rules'),
      p.join(sessionDir, '.gemini', 'skills'),
    ]) {
      await _syncSkillLinks(
        skillsDir: skillsDir,
        enabledSkillIds: enabledSkillIds,
        globalSkillsDir: _skillsDir,
      );
    }

    await _syncSkillLinks(
      skillsDir: p.join(sessionDir, '.github', 'copilot'),
      enabledSkillIds: enabledSkillIds,
      globalSkillsDir: _skillsDir,
      linkStyle: _LinkStyle.copilot,
    );
  }

  Future<void> _syncSkillLinks({
    required String skillsDir,
    required List<String> enabledSkillIds,
    required String globalSkillsDir,
    _LinkStyle linkStyle = _LinkStyle.claude,
  }) async {
    final dir = Directory(skillsDir);
    await dir.create(recursive: true);

    final desired = <String>{};
    for (final skillId in enabledSkillIds) {
      final globalSkillPath = p.join(globalSkillsDir, skillId);
      if (await Directory(globalSkillPath).exists()) {
        desired.add(skillId);
      }
    }

    // Remove stale skill links.
    // Note: list() must not follow links — a symlink to an existing directory
    // would be reported as a Directory and never cleaned up.
    await for (final entity in dir.list(followLinks: false)) {
      final name = p.basename(entity.path);
      if (desired.contains(name)) continue;
      if (entity is Link) {
        await entity.delete();
      } else if (linkStyle == _LinkStyle.copilot && entity is Directory) {
        // Copilot entries are real directories holding a linked SKILL.md.
        await entity.delete(recursive: true);
      }
    }

    // Create missing skill links
    for (final skillId in desired) {
      final linkPath = p.join(skillsDir, skillId);
      final link = Link(linkPath);
      if (!await link.exists()) {
        final globalSkillPath = p.join(globalSkillsDir, skillId);
        if (linkStyle == _LinkStyle.copilot) {
          // For Copilot: link the SKILL.md file directly
          final skillMd = File(p.join(globalSkillPath, 'SKILL.md'));
          if (await skillMd.exists()) {
            await Directory(linkPath).create(recursive: true);
            final mdLink = Link(p.join(linkPath, 'SKILL.md'));
            if (!await mdLink.exists()) {
              await mdLink.create(skillMd.path);
            }
          }
        } else {
          // Claude pattern: symlink entire skill directory
          await link.create(globalSkillPath);
        }
      }
    }
  }

  // ── Install to specific repo ─────────────────────────────────────────────────

  /// Copies (not symlinks) a skill into a specific repo path.
  /// Creates {repoPath}/.agents/skills/{skillId}/SKILL.md
  Future<SkillInstallResult> installSkillToRepo(SkillEntry skill, String repoPath) async {
    final globalSkillPath = Directory(p.join(_skillsDir, skill.id));
    if (!await globalSkillPath.exists()) {
      return SkillInstallResult.error(
        skill.id,
        'Skill not installed globally. Install it first from the Skills Store.',
      );
    }

    final destPath = p.join(repoPath, '.agents', 'skills', skill.id);
    final dest = Directory(destPath);
    if (await dest.exists()) {
      return SkillInstallResult.alreadyInstalled(skill.id);
    }

    try {
      await _copyDirectory(globalSkillPath, dest);
      return SkillInstallResult.success(skill.id);
    } catch (e) {
      return SkillInstallResult.error(skill.id, e.toString());
    }
  }

  // ── Uninstall ────────────────────────────────────────────────────────────────

  /// Removes a skill from the global skills dir and all workspace symlinks.
  Future<void> uninstallGlobalSkill(String skillId, List<Workspace> workspaces) async {
    // Remove from all workspace symlinks first
    for (final ws in workspaces) {
      for (final skillsPath in [
        _claudeSkillsPath(ws.workspaceDir),
        _cursorSkillsPath(ws.workspaceDir),
        _windsurfSkillsPath(ws.workspaceDir),
        _geminiSkillsPath(ws.workspaceDir),
      ]) {
        final link = Link(p.join(skillsPath, skillId));
        if (await link.exists()) await link.delete();
      }
      final copilotDir = Directory(p.join(_copilotSkillsPath(ws.workspaceDir), skillId));
      if (await copilotDir.exists()) await copilotDir.delete(recursive: true);
    }

    // Remove global copy
    final globalSkillDir = Directory(p.join(_skillsDir, skillId));
    if (await globalSkillDir.exists()) {
      await globalSkillDir.delete(recursive: true);
    }
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Future<void> _copyDirectory(Directory src, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in src.list(recursive: false)) {
      final destPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(destPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(destPath));
      }
    }
  }
}

enum _LinkStyle { claude, copilot }

// ── SkillInstallResult ────────────────────────────────────────────────────────

class SkillInstallResult {
  const SkillInstallResult._({
    required this.skillId,
    required this.status,
    this.message,
  });

  final String skillId;
  final SkillInstallStatus status;
  final String? message;

  factory SkillInstallResult.success(String skillId) =>
      SkillInstallResult._(skillId: skillId, status: SkillInstallStatus.success);

  factory SkillInstallResult.alreadyInstalled(String skillId) =>
      SkillInstallResult._(skillId: skillId, status: SkillInstallStatus.alreadyInstalled);

  factory SkillInstallResult.error(String skillId, String message) =>
      SkillInstallResult._(skillId: skillId, status: SkillInstallStatus.error, message: message);

  factory SkillInstallResult.requiresTerminal(String skillId, String command) =>
      SkillInstallResult._(
        skillId: skillId,
        status: SkillInstallStatus.requiresTerminal,
        message: command,
      );

  bool get isSuccess =>
      status == SkillInstallStatus.success ||
      status == SkillInstallStatus.alreadyInstalled;
}

enum SkillInstallStatus { success, alreadyInstalled, error, requiresTerminal }
