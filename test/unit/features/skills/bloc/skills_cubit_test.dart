import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/skills/bloc/skills_cubit.dart';
import 'package:yoloit/features/skills/bloc/skills_state.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;
  late String skillsDir;
  late SkillsCubit cubit;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('skills-cubit-test-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    skillsDir = PlatformDirs.instance.skillsDir;
    cubit = SkillsCubit();
  });

  tearDown(() async {
    await cubit.close();
    PlatformDirs.reset();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  Future<SkillsLoaded> loadCubit() async {
    await cubit.load(const []);
    final state = cubit.state;
    expect(state, isA<SkillsLoaded>());
    return state as SkillsLoaded;
  }

  SkillEntry skillIn(String id, {bool installed = false}) {
    return SkillEntry(
      id: id,
      name: id,
      description: 'desc',
      source: 'local',
      sourceType: SkillSourceType.local,
      isInstalled: installed,
    );
  }

  group('installSkill', () {
    test('is a no-op before the store is loaded', () async {
      await cubit.installSkill(skillIn('x'));

      expect(cubit.state, isA<SkillsInitial>());
    });

    test('reports manual installation for url-sourced skills', () async {
      await loadCubit();
      const skill = SkillEntry(
        id: 'web-skill',
        name: 'Web Skill',
        description: 'desc',
        source: 'https://example.com/skill',
        sourceType: SkillSourceType.url,
        installUrl: 'https://example.com/docs',
      );

      await cubit.installSkill(skill);

      final state = cubit.state as SkillsLoaded;
      expect(state.busySkillIds, isEmpty);
      expect(state.errorMessage, contains('Manual installation required'));
      expect(state.errorMessage, contains('https://example.com/docs'));
    });

    test('falls back to the source for local skills without an installUrl',
        () async {
      await loadCubit();
      const skill = SkillEntry(
        id: 'local-skill',
        name: 'Local Skill',
        description: 'desc',
        source: '/opt/skills/local-skill',
        sourceType: SkillSourceType.local,
      );

      await cubit.installSkill(skill);

      final state = cubit.state as SkillsLoaded;
      expect(state.errorMessage, contains('/opt/skills/local-skill'));
    });

    test('runs an install script and refreshes the installed list', () async {
      await loadCubit();
      const skill = SkillEntry(
        id: 'scripted',
        name: 'Scripted',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
        installCommand: 'echo done > out.txt',
      );

      await cubit.installSkill(skill);

      final state = cubit.state as SkillsLoaded;
      expect(state.busySkillIds, isEmpty);
      expect(state.errorMessage, isNull);
      expect(
        File(p.join(skillsDir, 'scripted', 'out.txt')).readAsStringSync(),
        'done\n',
      );
      // The refresh picked up the newly installed skill directory.
      final installed = state.skills.firstWhere((s) => s.id == 'scripted');
      expect(installed.isInstalled, isTrue);
    });

    test('treats an already-installed github skill as success', () async {
      await Directory(p.join(skillsDir, 'alpha')).create(recursive: true);
      await File(
        p.join(skillsDir, 'alpha', 'SKILL.md'),
      ).writeAsString('# alpha\n');
      await loadCubit();
      const skill = SkillEntry(
        id: 'alpha',
        name: 'Alpha',
        description: 'desc',
        source: 'owner/repo',
        sourceType: SkillSourceType.github,
      );

      await cubit.installSkill(skill);

      final state = cubit.state as SkillsLoaded;
      expect(state.busySkillIds, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test('surfaces install script failures as an error message', () async {
      await loadCubit();
      const skill = SkillEntry(
        id: 'failing',
        name: 'Failing',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
        installCommand: 'exit 3',
      );

      await cubit.installSkill(skill);

      final state = cubit.state as SkillsLoaded;
      expect(state.busySkillIds, isEmpty);
      expect(state.errorMessage, contains('exit 3'));
    });

    test('ignores a second install while the skill is busy', () async {
      await loadCubit();
      const skill = SkillEntry(
        id: 'slow',
        name: 'Slow',
        description: 'desc',
        source: 'local',
        sourceType: SkillSourceType.installScript,
        installCommand: 'sleep 1; echo done > out.txt',
      );

      final first = cubit.installSkill(skill);
      // Give the first call a chance to mark the skill busy.
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(
        (cubit.state as SkillsLoaded).busySkillIds,
        contains('slow'),
      );

      // The second call returns immediately without disturbing state.
      await cubit.installSkill(skill);
      expect(
        (cubit.state as SkillsLoaded).busySkillIds,
        contains('slow'),
      );

      await first;
      expect((cubit.state as SkillsLoaded).busySkillIds, isEmpty);
    });
  });
}
