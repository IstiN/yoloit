import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'auto_tools.dart is up-to-date with the CLI registry',
    () async {
      final repoRoot = Directory.current.path;
      final expectedFile = File(
        p.join(
          repoRoot,
          'lib',
          'features',
          'board',
          'chat',
          'cli_tools',
          'auto_tools.dart',
        ),
      );
      expect(
        await expectedFile.exists(),
        isTrue,
        reason: 'Committed auto_tools.dart should exist',
      );
      final expected = await expectedFile.readAsString();

      final result = await Process.run(
        'dart',
        <String>[
          'run',
          p.join(repoRoot, 'tool', 'generate_auto_tools.dart'),
        ],
      );

      expect(
        result.exitCode,
        0,
        reason: 'Generator failed: stdout=${result.stdout} '
            'stderr=${result.stderr}',
      );

      final generated = await expectedFile.readAsString();

      expect(
        generated,
        expected,
        reason: 'auto_tools.dart was modified by the generator. '
            'Run: dart run tool/generate_auto_tools.dart',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
