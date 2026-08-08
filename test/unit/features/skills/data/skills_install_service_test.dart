import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/skills/data/skills_install_service.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';
import 'package:yoloit/features/workspaces/models/workspace.dart';

void main() {
  late Directory home;
  late String skillsDir;

  const ghSkill = SkillEntry(
    id: 'alpha',
    name: 'Alpha Skill',
    description: 'alpha desc',
    source: 'owner/repo',
    sourceType: SkillSourceType.github,
  );

  setUp(() async {
    home = await Directory.systemTemp.createTemp('skills-install-test-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    skillsDir = PlatformDirs.instance.skillsDir;
  });

  tearDown(() async {
    PlatformDirs.reset();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  Future<Directory> createGlobalSkill(String id, {bool withSkillMd = true}) async {
    final dir = Directory(p.join(skillsDir, id));
    await dir.create(recursive: true);
    if (withSkillMd) {
      await File(p.join(dir.path, 'SKILL.md')).writeAsString('# $id\n');
    }
    return dir;
  }

  Future<bool> entityExists(String path) =>
      FileSystemEntity.type(path, followLinks: false)
          .then((type) => type != FileSystemEntityType.notFound);

  group('installGithubSkill', () {
    test('returns alreadyInstalled when destination exists', () async {
      await createGlobalSkill(ghSkill.id);

      final result = await SkillsInstallService.instance.installGithubSkill(ghSkill);

      expect(result.status, SkillInstallStatus.alreadyInstalled);
      expect(result.isSuccess, isTrue);
    });

    test('returns error for invalid source without touching the network', () async {
      const badSkill = SkillEntry(
        id: 'bad',
        name: 'Bad',
        description: 'bad',
        source: 'noslash',
        sourceType: SkillSourceType.github,
      );

      final result = await SkillsInstallService.instance.installGithubSkill(badSkill);

      expect(result.status, SkillInstallStatus.error);
      expect(result.message, contains('gh'));
    });
  });

  group('runInstallScript', () {
    const scriptSkill = SkillEntry(
      id: 'scripted',
      name: 'Scripted Skill',
      description: 'script desc',
      source: 'local',
      sourceType: SkillSourceType.installScript,
      installCommand: 'echo hello > out.txt',
    );

    test('returns error when no install command is specified', () async {
      const noCmd = SkillEntry(
        id: 'nocmd',
        name: 'No Cmd',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
      );

      final result = await SkillsInstallService.instance.runInstallScript(noCmd);

      expect(result.status, SkillInstallStatus.error);
      expect(result.message, contains('No install command'));
    });

    test('runs the command and synthesizes SKILL.md when missing', () async {
      final result = await SkillsInstallService.instance.runInstallScript(scriptSkill);

      expect(result.status, SkillInstallStatus.success);

      final skillDir = p.join(skillsDir, scriptSkill.id);
      expect(await File(p.join(skillDir, 'out.txt')).readAsString(), 'hello\n');

      final skillMd = File(p.join(skillDir, 'SKILL.md'));
      expect(await skillMd.exists(), isTrue);
      expect(await skillMd.readAsString(), contains('# Scripted Skill'));
    });

    test('keeps an existing SKILL.md produced by the script', () async {
      const selfMd = SkillEntry(
        id: 'selfmd',
        name: 'Self Md',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
        installCommand: 'echo custom > SKILL.md',
      );

      final result = await SkillsInstallService.instance.runInstallScript(selfMd);

      expect(result.status, SkillInstallStatus.success);
      expect(
        await File(p.join(skillsDir, selfMd.id, 'SKILL.md')).readAsString(),
        'custom\n',
      );
    });

    test('reports failure and removes the empty skill dir', () async {
      const failing = SkillEntry(
        id: 'failing',
        name: 'Failing',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
        installCommand: 'echo oops >&2; exit 3',
      );

      final result = await SkillsInstallService.instance.runInstallScript(failing);

      expect(result.status, SkillInstallStatus.error);
      expect(result.message, contains('exit 3'));
      expect(result.message, contains('oops'));
      expect(await Directory(p.join(skillsDir, failing.id)).exists(), isFalse);
    });
  });

  group('syncWorkspaceSkills', () {
    test('creates links for all providers and skips unknown skills', () async {
      await createGlobalSkill('alpha');
      await createGlobalSkill('nomd', withSkillMd: false);
      const workspace = Workspace(
        id: 'ws_1',
        name: 'ws',
        paths: ['/tmp/repo'],
        enabledSkills: ['alpha', 'nomd', 'ghost'],
      );

      await SkillsInstallService.instance.syncWorkspaceSkills(workspace);

      final wsDir = workspace.workspaceDir;
      for (final rel in [
        p.join('.claude', 'commands'),
        p.join('.cursor', 'rules'),
        p.join('.windsurf', 'rules'),
        p.join('.gemini', 'skills'),
      ]) {
        expect(
          await entityExists(p.join(wsDir, rel, 'alpha')),
          isTrue,
          reason: 'missing link in $rel',
        );
        // 'ghost' is not installed globally, so no link is created.
        expect(await entityExists(p.join(wsDir, rel, 'ghost')), isFalse);
      }

      // Copilot style links the SKILL.md file directly.
      expect(
        await File(p.join(wsDir, '.github', 'copilot', 'alpha', 'SKILL.md')).exists(),
        isTrue,
      );
      // 'nomd' has no SKILL.md, so the copilot link is skipped while the
      // directory symlink is still created.
      expect(
        await entityExists(p.join(wsDir, '.github', 'copilot', 'nomd')),
        isFalse,
      );
      expect(
        await entityExists(p.join(wsDir, '.claude', 'commands', 'nomd')),
        isTrue,
      );
    });

    test('removes stale links and keeps desired ones', () async {
      await createGlobalSkill('alpha');
      const workspace = Workspace(
        id: 'ws_2',
        name: 'ws',
        paths: ['/tmp/repo'],
        enabledSkills: ['alpha'],
      );
      final wsDir = workspace.workspaceDir;

      // Pre-seed a stale link that is not in the desired set.
      final claudeDir = Directory(p.join(wsDir, '.claude', 'commands'));
      await claudeDir.create(recursive: true);
      await Link(p.join(claudeDir.path, 'stale'))
          .create(p.join(skillsDir, 'stale'));

      await SkillsInstallService.instance.syncWorkspaceSkills(workspace);

      expect(
        await entityExists(p.join(claudeDir.path, 'stale')),
        isFalse,
      );
      expect(
        await entityExists(p.join(claudeDir.path, 'alpha')),
        isTrue,
      );

      // Sync is idempotent for links that already exist.
      await SkillsInstallService.instance.syncWorkspaceSkills(workspace);
      expect(
        await entityExists(p.join(claudeDir.path, 'alpha')),
        isTrue,
      );

      // Disabling all skills removes every link.
      await SkillsInstallService.instance.syncWorkspaceSkills(
        workspace.copyWith(enabledSkills: const []),
      );
      expect(
        await entityExists(p.join(claudeDir.path, 'alpha')),
        isFalse,
      );
      expect(
        await entityExists(p.join(wsDir, '.github', 'copilot', 'alpha')),
        isFalse,
      );
    });
  });

  group('syncSessionSkills', () {
    test('links skills into the session directory', () async {
      await createGlobalSkill('alpha');
      final sessionDir = p.join(home.path, 'session');

      await SkillsInstallService.instance.syncSessionSkills(
        sessionDir: sessionDir,
        enabledSkillIds: const ['alpha', 'ghost'],
      );

      for (final rel in [
        p.join('.claude', 'commands'),
        p.join('.cursor', 'rules'),
        p.join('.windsurf', 'rules'),
        p.join('.gemini', 'skills'),
      ]) {
        expect(await entityExists(p.join(sessionDir, rel, 'alpha')), isTrue);
      }
      expect(
        await File(p.join(sessionDir, '.github', 'copilot', 'alpha', 'SKILL.md'))
            .exists(),
        isTrue,
      );
      expect(
        await entityExists(p.join(sessionDir, '.claude', 'commands', 'ghost')),
        isFalse,
      );
    });
  });

  group('installSkillToRepo', () {
    test('returns error when the skill is not installed globally', () async {
      final repo = p.join(home.path, 'repo');

      final result = await SkillsInstallService.instance
          .installSkillToRepo(ghSkill, repo);

      expect(result.status, SkillInstallStatus.error);
      expect(result.message, contains('not installed globally'));
    });

    test('copies the skill into the repo and reports alreadyInstalled on rerun',
        () async {
      final globalDir = await createGlobalSkill('alpha');
      final nested = Directory(p.join(globalDir.path, 'refs'));
      await nested.create();
      await File(p.join(nested.path, 'notes.md')).writeAsString('notes\n');
      final repo = p.join(home.path, 'repo');

      final result = await SkillsInstallService.instance
          .installSkillToRepo(ghSkill, repo);

      expect(result.status, SkillInstallStatus.success);
      final dest = p.join(repo, '.agents', 'skills', 'alpha');
      expect(await File(p.join(dest, 'SKILL.md')).exists(), isTrue);
      expect(
        await File(p.join(dest, 'refs', 'notes.md')).readAsString(),
        'notes\n',
      );

      final rerun = await SkillsInstallService.instance
          .installSkillToRepo(ghSkill, repo);
      expect(rerun.status, SkillInstallStatus.alreadyInstalled);
    });
  });

  group('uninstallGlobalSkill', () {
    test('removes workspace links, copilot dirs and the global copy', () async {
      await createGlobalSkill('alpha');
      const workspace = Workspace(
        id: 'ws_3',
        name: 'ws',
        paths: ['/tmp/repo'],
        enabledSkills: ['alpha'],
      );
      await SkillsInstallService.instance.syncWorkspaceSkills(workspace);
      final wsDir = workspace.workspaceDir;
      expect(
        await entityExists(p.join(wsDir, '.claude', 'commands', 'alpha')),
        isTrue,
      );

      await SkillsInstallService.instance
          .uninstallGlobalSkill('alpha', [workspace]);

      for (final rel in [
        p.join('.claude', 'commands'),
        p.join('.cursor', 'rules'),
        p.join('.windsurf', 'rules'),
        p.join('.gemini', 'skills'),
      ]) {
        expect(await entityExists(p.join(wsDir, rel, 'alpha')), isFalse);
      }
      expect(
        await entityExists(p.join(wsDir, '.github', 'copilot', 'alpha')),
        isFalse,
      );
      expect(await Directory(p.join(skillsDir, 'alpha')).exists(), isFalse);
    });

    test('tolerates missing links and missing global dir', () async {
      const workspace = Workspace(
        id: 'ws_4',
        name: 'ws',
        paths: ['/tmp/repo'],
      );

      await SkillsInstallService.instance
          .uninstallGlobalSkill('never-existed', [workspace]);

      expect(await Directory(p.join(skillsDir, 'never-existed')).exists(), isFalse);
    });
  });
}
