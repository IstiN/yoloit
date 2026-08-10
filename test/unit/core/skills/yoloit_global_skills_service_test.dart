import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';
import 'package:yoloit/core/skills/yoloit_global_skills_service.dart';

void main() {
  late Directory home;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('yoloit-skills-home-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
  });

  tearDown(() async {
    PlatformDirs.setInstance(const MacosPlatformDirs());
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  test(
    'installOrUpdate creates built-in skill and syncs all global harnesses',
    () async {
      final lines =
          await YoloitGlobalSkillsService.instance.installOrUpdate().toList();

      expect(lines.join('\n'), contains('YoLoIT global skills are ready'));

      final skillFile = File(
        p.join(
          PlatformDirs.instance.skillsDir,
          YoloitGlobalSkillsService.builtInSkillId,
          'SKILL.md',
        ),
      );
      expect(await skillFile.exists(), isTrue);

      final service = YoloitGlobalSkillsService.instance;
      for (final target in service.targets) {
        final skillPath = p.join(
          target.path,
          YoloitGlobalSkillsService.builtInSkillId,
        );
        if (target.linkStyle == GlobalSkillLinkStyle.copilotSkillFile) {
          expect(await File(p.join(skillPath, 'SKILL.md')).exists(), isTrue);
        } else {
          expect(
            await Directory(skillPath).exists() ||
                await Link(skillPath).exists(),
            isTrue,
            reason: target.name,
          );
        }
      }

      final status = await service.check();
      expect(status.installed, isTrue);
      expect(
        status.skillIds,
        contains(YoloitGlobalSkillsService.builtInSkillId),
      );
    },
  );

  test(
    'copyDirectoryForTest copies files and nested directories recursively',
    () async {
      final source = Directory(p.join(home.path, 'src'));
      final nested = Directory(p.join(source.path, 'nested', 'deep'));
      await nested.create(recursive: true);
      await File(p.join(source.path, 'SKILL.md')).writeAsString('# skill\n');
      await File(p.join(nested.path, 'notes.md')).writeAsString('notes\n');
      final dest = Directory(p.join(home.path, 'out', 'dest'));

      await YoloitGlobalSkillsService.instance
          .copyDirectoryForTest(source, dest);

      expect(
        await File(p.join(dest.path, 'SKILL.md')).readAsString(),
        '# skill\n',
      );
      expect(
        await File(p.join(dest.path, 'nested', 'deep', 'notes.md'))
            .readAsString(),
        'notes\n',
      );
    },
  );

  test(
    'SetupCatalog exposes YoLoIT global skills as a special install task',
    () {
      final package = SetupCatalog.packages.singleWhere(
        (pkg) => pkg.id == SetupCatalog.yoloitSkillsPackageId,
      );

      expect(package.name, 'YoLoIT Global Skills');
      expect(SetupCatalog.isSpecialInstallTask(package.id), isTrue);

      final script = SetupCatalog.installScript(<String>[
        SetupCatalog.yoloitSkillsPackageId,
        'git',
      ], SetupTargetOs.linux);

      expect(script, contains('apt-get install -y git'));
      expect(script, isNot(contains('__yoloit_global_skills__')));
    },
  );
}
