import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';

enum GlobalSkillLinkStyle { directory, copilotSkillFile }

class GlobalSkillTarget {
  const GlobalSkillTarget({
    required this.id,
    required this.name,
    required this.path,
    this.linkStyle = GlobalSkillLinkStyle.directory,
  });

  final String id;
  final String name;
  final String path;
  final GlobalSkillLinkStyle linkStyle;
}

class GlobalSkillsStatus {
  const GlobalSkillsStatus({
    required this.skillsDir,
    required this.skillIds,
    required this.targets,
    required this.missingTargets,
  });

  final String skillsDir;
  final List<String> skillIds;
  final List<GlobalSkillTarget> targets;
  final List<GlobalSkillTarget> missingTargets;

  bool get hasSkills => skillIds.isNotEmpty;
  bool get installed => hasSkills && missingTargets.isEmpty;

  String get summary {
    if (!hasSkills) return 'No YoLoIT skills installed yet';
    if (installed) {
      return '${skillIds.length} skill(s) linked to ${targets.length} harnesses';
    }
    return '${skillIds.length} skill(s), ${missingTargets.length} harness target(s) missing';
  }
}

class YoloitGlobalSkillsService {
  YoloitGlobalSkillsService._();
  static final instance = YoloitGlobalSkillsService._();

  static const builtInSkillId = 'yoloit-app-development';
  static const yoloitSkillId = 'yoloit';

  String get _home {
    final configDir = PlatformDirs.instance.configDir;
    if (p.basename(configDir) == 'yoloit' &&
        p.basename(p.dirname(configDir)) == '.config') {
      return p.dirname(p.dirname(configDir));
    }
    return Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.current.path;
  }

  String get _skillsDir => PlatformDirs.instance.skillsDir;

  List<GlobalSkillTarget> get targets => <GlobalSkillTarget>[
    GlobalSkillTarget(
      id: 'codex',
      name: 'Codex CLI',
      path: p.join(_home, '.codex', 'skills'),
    ),
    GlobalSkillTarget(
      id: 'claude',
      name: 'Claude Code',
      path: p.join(_home, '.claude', 'commands'),
    ),
    GlobalSkillTarget(
      id: 'cursor',
      name: 'Cursor',
      path: p.join(_home, '.cursor', 'rules'),
    ),
    GlobalSkillTarget(
      id: 'copilot',
      name: 'GitHub Copilot',
      path: p.join(_home, '.github', 'copilot'),
      linkStyle: GlobalSkillLinkStyle.copilotSkillFile,
    ),
    GlobalSkillTarget(
      id: 'gemini',
      name: 'Gemini CLI',
      path: p.join(_home, '.gemini', 'skills'),
    ),
    GlobalSkillTarget(
      id: 'windsurf',
      name: 'Windsurf',
      path: p.join(_home, '.windsurf', 'rules'),
    ),
    GlobalSkillTarget(
      id: 'kimi-user',
      name: 'Kimi Agent',
      path: p.join(_home, '.agents', 'skills'),
    ),
  ];

  Future<GlobalSkillsStatus> check() async {
    final skillIds = await _installedSkillIds();
    final missing = <GlobalSkillTarget>[];
    for (final target in targets) {
      if (!await _targetHasSkills(target, skillIds)) {
        missing.add(target);
      }
    }
    return GlobalSkillsStatus(
      skillsDir: _skillsDir,
      skillIds: skillIds,
      targets: targets,
      missingTargets: missing,
    );
  }

  Stream<String> installOrUpdate() {
    final controller = StreamController<String>();
    () async {
      try {
        controller.add('Ensuring built-in YoLoIT skill exists');
        await ensureBuiltInSkill();
        final skillIds = await _installedSkillIds();
        if (skillIds.isEmpty) {
          controller.add('No skills found in $_skillsDir');
          return;
        }
        controller.add('Syncing ${skillIds.length} skill(s) from $_skillsDir');
        for (final target in targets) {
          await _syncTarget(target, skillIds);
          controller.add('Synced ${target.name}: ${target.path}');
        }
        controller.add('YoLoIT global skills are ready');
      } catch (error) {
        controller.add('Error: $error');
      } finally {
        await controller.close();
      }
    }();
    return controller.stream;
  }

  Future<void> ensureBuiltInSkill() async {
    await _ensureAppDevelopmentSkill();
    await _ensureYoloitSkill();
  }

  Future<void> _ensureAppDevelopmentSkill() async {
    final skillDir = Directory(p.join(_skillsDir, builtInSkillId));
    await skillDir.create(recursive: true);
    final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
    await skillFile.writeAsString(await _builtInSkillContent());
  }

  Future<void> _ensureYoloitSkill() async {
    final skillDir = Directory(p.join(_skillsDir, yoloitSkillId));
    await skillDir.create(recursive: true);
    final skillFile = File(p.join(skillDir.path, 'SKILL.md'));
    final content = await rootBundle.loadString(
      'assets/skills/yoloit/SKILL.md',
    );
    await skillFile.writeAsString(content);
  }

  Future<List<String>> _installedSkillIds() async {
    final dir = Directory(_skillsDir);
    if (!await dir.exists()) return const <String>[];
    final ids = <String>[];
    await for (final entity in dir.list()) {
      if (entity is! Directory) continue;
      final id = p.basename(entity.path);
      if (id.startsWith('_tmp_')) continue;
      if (await File(p.join(entity.path, 'SKILL.md')).exists()) {
        ids.add(id);
      }
    }
    ids.sort();
    return ids;
  }

  Future<bool> _targetHasSkills(
    GlobalSkillTarget target,
    List<String> skillIds,
  ) async {
    if (skillIds.isEmpty) return false;
    final dir = Directory(target.path);
    if (!await dir.exists()) return false;
    for (final skillId in skillIds) {
      final skillPath = p.join(target.path, skillId);
      final hasSkill =
          target.linkStyle == GlobalSkillLinkStyle.copilotSkillFile
              ? await File(p.join(skillPath, 'SKILL.md')).exists()
              : await Directory(skillPath).exists() ||
                  await Link(skillPath).exists();
      if (!hasSkill) return false;
    }
    return true;
  }

  Future<void> _syncTarget(
    GlobalSkillTarget target,
    List<String> skillIds,
  ) async {
    await Directory(target.path).create(recursive: true);
    for (final skillId in skillIds) {
      final source = Directory(p.join(_skillsDir, skillId));
      if (!await source.exists()) continue;
      final destination = p.join(target.path, skillId);
      if (target.linkStyle == GlobalSkillLinkStyle.copilotSkillFile) {
        await Directory(destination).create(recursive: true);
        await _replaceWithLinkOrCopy(
          File(p.join(source.path, 'SKILL.md')),
          p.join(destination, 'SKILL.md'),
        );
      } else {
        await _replaceWithLinkOrCopy(source, destination);
      }
    }
  }

  Future<void> _replaceWithLinkOrCopy(
    FileSystemEntity source,
    String dest,
  ) async {
    await _deleteIfExists(dest);
    if (!Platform.isWindows) {
      try {
        await Link(dest).create(source.path, recursive: true);
        return;
      } catch (_) {
        await _deleteIfExists(dest);
      }
    }
    if (source is File) {
      await Directory(p.dirname(dest)).create(recursive: true);
      await source.copy(dest);
      return;
    }
    if (source is Directory) {
      await _copyDirectory(source, Directory(dest));
    }
  }

  Future<void> _deleteIfExists(String path) async {
    final link = Link(path);
    if (await link.exists()) {
      await link.delete();
      return;
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
      return;
    }
    final dir = Directory(path);
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
  }

  /// Test hook for [_copyDirectory] (the production call site only runs when
  /// symlinking fails, which is hard to force deterministically in tests).
  @visibleForTesting
  Future<void> copyDirectoryForTest(Directory source, Directory dest) =>
      _copyDirectory(source, dest);

  Future<void> _copyDirectory(Directory source, Directory dest) async {
    await dest.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final targetPath = p.join(dest.path, p.basename(entity.path));
      if (entity is File) {
        await entity.copy(targetPath);
      } else if (entity is Directory) {
        await _copyDirectory(entity, Directory(targetPath));
      }
    }
  }

  Future<String> _builtInSkillContent() async {
    final candidates = <String>[
      p.join(Directory.current.path, 'docs', 'app-development-skill.md'),
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'docs',
        'app-development-skill.md',
      ),
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        return file.readAsString();
      }
    }
    return '''
# YoLoIT App Development Skill

Use the YoLoIT CLI for board and widget work. Prefer `yoloit app:dev-skill`
for the full current guide, `yoloit panel:types` before creating unknown panel
types, and `yoloit app:run .` plus `yoloit app:reload .` for local widget
development.
''';
  }
}
