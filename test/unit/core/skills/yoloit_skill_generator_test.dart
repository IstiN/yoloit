import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'built-in yoloit skill asset is up-to-date with tools/yoloit commands',
    () async {
      final repoRoot = Directory.current.path;
      final expectedFile = File(
        p.join(repoRoot, 'assets', 'skills', 'yoloit', 'SKILL.md'),
      );
      expect(
        await expectedFile.exists(),
        isTrue,
        reason: 'Committed skill asset should exist',
      );
      final expected = await expectedFile.readAsString();

      final tempDir = await Directory.systemTemp.createTemp(
        'yoloit_skill_generator_test',
      );
      final tempOut = p.join(tempDir.path, 'SKILL.md');
      final result = await Process.run(
        'python3',
        <String>[
          p.join(repoRoot, 'tools', 'generate_yoloit_skill.py'),
          '--output',
          tempOut,
        ],
      );

      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      expect(
        result.exitCode,
        0,
        reason: 'Generator failed: stdout=${result.stdout} '
            'stderr=${result.stderr}',
      );

      final generatedFile = File(tempOut);
      expect(
        await generatedFile.exists(),
        isTrue,
        reason: 'Generator should produce ${tempOut}',
      );
      final generated = await generatedFile.readAsString();

      expect(
        generated,
        expected,
        reason: 'assets/skills/yoloit/SKILL.md is out of sync with '
            'tools/yoloit. Run: python3 tools/generate_yoloit_skill.py',
      );
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
