import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/skills/data/skills_store_service.dart';
import 'package:yoloit/features/skills/models/skill_entry.dart';

void main() {
  late Directory home;
  late String skillsDir;

  setUp(() async {
    home = await Directory.systemTemp.createTemp('skills-store-test-');
    PlatformDirs.setInstance(LinuxPlatformDirs(homeOverride: home.path));
    skillsDir = PlatformDirs.instance.skillsDir;
  });

  tearDown(() async {
    PlatformDirs.reset();
    if (await home.exists()) {
      await home.delete(recursive: true);
    }
  });

  Future<void> createSkill(String id, {String? skillMd}) async {
    final dir = Directory(p.join(skillsDir, id));
    await dir.create(recursive: true);
    if (skillMd != null) {
      await File(p.join(dir.path, 'SKILL.md')).writeAsString(skillMd);
    }
  }

  group('SkillsStoreService.refresh (description/name extraction)', () {
    test('returns empty list when skills dir does not exist', () async {
      await SkillsStoreService.instance.refresh();
      final local =
          SkillsStoreService.instance.availableSkills
              .where((s) => s.sourceType == SkillSourceType.local)
              .toList();
      expect(local, isEmpty);
    });

    test('extracts description from a description: front-matter line', () async {
      await createSkill(
        'fm-skill',
        skillMd: '---\nname: Fancy Name\ndescription:   Does fancy things  \n---\n# Body\n',
      );

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'fm-skill',
      );

      expect(skill.name, 'Fancy Name');
      expect(skill.description, 'Does fancy things');
      expect(skill.isInstalled, isTrue);
    });

    test('falls back to the first meaningful body line', () async {
      await createSkill(
        'body-skill',
        skillMd: '---\nname: Body Skill\n---\n\n# Heading is skipped\nUse this skill for bodies.\n',
      );

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'body-skill',
      );

      expect(skill.name, 'Body Skill');
      expect(skill.description, 'Use this skill for bodies.');
    });

    test('truncates a fallback description longer than 120 chars', () async {
      final longLine = 'x' * 200;
      await createSkill('long-skill', skillMd: '$longLine\n');

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'long-skill',
      );

      expect(skill.description.length, 121);
      expect(skill.description, '${'x' * 120}…');
    });

    test('returns empty description when only comments/front-matter exist',
        () async {
      await createSkill(
        'empty-skill',
        skillMd: '---\nname: Only Meta\n---\n# just a comment\n\n---\n',
      );

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'empty-skill',
      );

      expect(skill.name, 'Only Meta');
      expect(skill.description, '');
    });

    test('uses directory id as name when SKILL.md is missing', () async {
      await createSkill('bare-skill');

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'bare-skill',
      );

      expect(skill.name, 'bare-skill');
      expect(skill.description, '');
      expect(skill.isInstalled, isTrue);
    });

    test('marks catalog skills as installed when a matching directory exists',
        () async {
      // 'flutter-architecting-apps' is part of the built-in catalog.
      await createSkill('flutter-architecting-apps');

      await SkillsStoreService.instance.refresh();
      final skill = SkillsStoreService.instance.availableSkills.firstWhere(
        (s) => s.id == 'flutter-architecting-apps',
      );

      expect(skill.isInstalled, isTrue);
      expect(skill.sourceType, SkillSourceType.github);
    });
  });
}
