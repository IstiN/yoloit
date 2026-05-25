import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

void main() {
  group('YoloitCliToolCatalog.catalogJson', () {
    test('returns valid JSON with commands/coverage keys', () {
      final json = YoloitCliToolCatalog.catalogJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded, containsPair('commands', isA<List>()));
      expect(decoded, containsPair('coverage', isA<Map>()));
      final coverage = decoded['coverage'] as Map<String, dynamic>;
      expect(coverage['total'], greaterThan(0));
    });

    test('coverage total equals number of tools', () {
      final json = YoloitCliToolCatalog.catalogJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final coverage = decoded['coverage'] as Map<String, dynamic>;
      expect(coverage['total'], equals(YoloitCliToolCatalog.tools.length));
    });

    test('withVariants + missing.length == total', () {
      final json = YoloitCliToolCatalog.catalogJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final coverage = decoded['coverage'] as Map<String, dynamic>;
      final total = coverage['total'] as int;
      final withVariants = coverage['withVariants'] as int;
      final missing = (coverage['missing'] as List).length;
      expect(withVariants + missing, equals(total));
    });

    test('each command entry has required fields', () {
      final json = YoloitCliToolCatalog.catalogJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final commands = decoded['commands'] as List;
      for (final cmd in commands) {
        final m = cmd as Map<String, dynamic>;
        expect(m['command'], isA<String>());
        expect(m['description'], isA<String>());
        expect(m['human'], isA<Map>());
      }
    });

    test('merges extra YAML variants into catalogJson output', () {
      const fakeYaml = <String, Map<String, List<String>>>{
        'reload': {
          'en': ['restart app', 'reload yoloit'],
          'ru': ['перезапусти'],
        },
      };
      final json = YoloitCliToolCatalog.catalogJson(fakeYaml);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final commands = decoded['commands'] as List<dynamic>;
      final reloadCmd = commands.firstWhere(
        (c) => (c as Map)['command'] == 'reload',
        orElse: () => null,
      );
      if (reloadCmd != null) {
        final human = (reloadCmd as Map<String, dynamic>)['human']
            as Map<String, dynamic>;
        final en = (human['en'] as List).cast<String>();
        expect(en, containsAll(['restart app', 'reload yoloit']));
      }
    });

    test('YAML variants do not duplicate built-in variants', () {
      // Inject a variant that already exists for a command that has variants
      final toolWithVariants = YoloitCliToolCatalog.tools.firstWhere(
        (t) => t.humanVariants.isNotEmpty,
        orElse: () => YoloitCliToolCatalog.tools.first,
      );
      final cmd = toolWithVariants.command;
      final extra = <String, Map<String, List<String>>>{
        cmd: {
          'en': ['__unique_extra_phrase__'],
        },
      };
      final json = YoloitCliToolCatalog.catalogJson(extra);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final commands = decoded['commands'] as List;
      final found = commands.firstWhere(
        (c) => (c as Map)['command'] == cmd,
        orElse: () => null,
      );
      if (found != null) {
        final human = (found as Map<String, dynamic>)['human']
            as Map<String, dynamic>;
        final en = ((human['en'] ?? []) as List).cast<String>();
        expect(en, contains('__unique_extra_phrase__'));
      }
    });

    test('catalogJson without yamlVariants matches pre-YAML tools coverage', () {
      final json = YoloitCliToolCatalog.catalogJson();
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final coverage = decoded['coverage'] as Map<String, dynamic>;
      // At least some commands should have variants
      expect(coverage['withVariants'], greaterThan(0));
    });
  });

  group('YoloitCliToolCatalog tools sanity', () {
    test('no two tools share the same command name', () {
      final commands =
          YoloitCliToolCatalog.tools.map((t) => t.command).toList();
      final unique = commands.toSet();
      expect(unique.length, equals(commands.length));
    });

    test('all tools have non-empty description', () {
      for (final tool in YoloitCliToolCatalog.tools) {
        expect(
          tool.description,
          isNotEmpty,
          reason: 'Tool ${tool.command} missing description',
        );
      }
    });
  });
}
