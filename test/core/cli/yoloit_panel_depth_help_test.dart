import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'tools/yoloit exposes panel depth command for CLI-first control',
    () async {
      final syntax = await Process.run('bash', const ['-n', 'tools/yoloit']);
      expect(syntax.exitCode, 0, reason: syntax.stderr.toString());

      final result = await Process.run('tools/yoloit', const [
        'help',
        '--format',
        'tools',
      ]);
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final decoded =
          jsonDecode(result.stdout.toString()) as Map<String, dynamic>;
      final tools = decoded['tools'] as List<dynamic>;
      final panelZ = tools.cast<Map<dynamic, dynamic>>().singleWhere(
        (tool) => tool['name'] == 'panel:z',
      );

      expect(panelZ['description'], contains('depth'));
      expect(panelZ['aliases'], containsAll(['panel:front', 'panel:back']));
      final schema = panelZ['inputSchema'] as Map<dynamic, dynamic>;
      expect(schema['required'], containsAll(['board', 'panel']));
      expect(
        (schema['properties'] as Map<dynamic, dynamic>).keys,
        contains('front_or_back_or_zindex'),
      );
    },
  );
}
