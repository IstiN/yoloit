/// Router E2E tests — validates that the command catalog provides correct
/// coverage of expected commands and that human variants are well-formed.
///
/// These tests use in-process catalog data only (no CLI server required).
/// They serve as the "smoke board" validation suite for the router pipeline.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// Commands that MUST have human variants for the router to work.
const kRequiredCommands = [
  'boards',
  'board:focus',
  'board:create',
  'panels',
  'panel:focus',
  'note:create',
  'note:add',
];

/// Spot-check: for each entry, at least one locale phrase must contain the keyword.
const kPhraseKeywords = [
  ('boards', 'boards'),
  ('board:focus', 'board'),
  ('board:create', 'board'),
  ('panel:focus', 'panel'),
  ('note:create', 'note'),
];

void main() {
  late Map<String, YoloitCliTool> toolByCommand;
  late Map<String, dynamic> catalog;

  setUpAll(() {
    toolByCommand = {
      for (final t in YoloitCliToolCatalog.tools) t.command: t,
    };
    catalog = jsonDecode(YoloitCliToolCatalog.catalogJson())
        as Map<String, dynamic>;
  });

  group('Router E2E — catalog coverage', () {
    test('all required commands exist in tool registry', () {
      for (final cmd in kRequiredCommands) {
        expect(
          toolByCommand.containsKey(cmd),
          isTrue,
          reason: 'Missing required command: $cmd',
        );
      }
    });

    test('all required commands have at least one human variant', () {
      for (final cmd in kRequiredCommands) {
        final tool = toolByCommand[cmd];
        expect(
          tool,
          isNotNull,
          reason: 'Tool $cmd not found',
        );
        expect(
          tool!.humanVariants.isNotEmpty,
          isTrue,
          reason: 'Command $cmd has no human variants — router cannot learn it',
        );
      }
    });

    test('each variant locale contains at least 1 non-empty phrase', () {
      for (final tool in YoloitCliToolCatalog.tools) {
        for (final entry in tool.humanVariants.entries) {
          for (final phrase in entry.value) {
            expect(
              phrase.trim().isNotEmpty,
              isTrue,
              reason:
                  'Empty phrase for ${tool.command} locale ${entry.key}',
            );
          }
        }
      }
    });

    test('catalog commands list has no duplicate command IDs', () {
      final commands =
          (catalog['commands'] as List).cast<Map<String, dynamic>>();
      final ids = commands.map((c) => c['command'] as String).toList();
      expect(ids.toSet().length, equals(ids.length));
    });
  });

  group('Router E2E — phrase keyword spot-check', () {
    for (final (cmd, keyword) in kPhraseKeywords) {
      test('$cmd phrases contain "$keyword"', () {
        final tool = toolByCommand[cmd];
        if (tool == null || tool.humanVariants.isEmpty) {
          markTestSkipped('$cmd has no variants');
          return;
        }
        final allPhrases = tool.humanVariants.values
            .expand((phrases) => phrases)
            .map((p) => p.toLowerCase())
            .toList();
        final anyMatch =
            allPhrases.any((p) => p.contains(keyword.toLowerCase()));
        expect(
          anyMatch,
          isTrue,
          reason:
              'None of $cmd phrases contain "$keyword": $allPhrases',
        );
      });
    }
  });

  group('Router E2E — catalog JSON integrity', () {
    test('coverage.total >= 90 commands (registry is substantial)', () {
      final coverage = catalog['coverage'] as Map<String, dynamic>;
      expect(coverage['total'], greaterThanOrEqualTo(90));
    });

    test('at least 10 commands have human variants in Dart code', () {
      final coverage = catalog['coverage'] as Map<String, dynamic>;
      expect(coverage['withVariants'], greaterThanOrEqualTo(10));
    });

    test('missing commands list is a list of strings', () {
      final coverage = catalog['coverage'] as Map<String, dynamic>;
      final missing = coverage['missing'] as List;
      for (final m in missing) {
        expect(m, isA<String>());
      }
    });

    test('command entries have params field as list', () {
      final commands =
          (catalog['commands'] as List).cast<Map<String, dynamic>>();
      for (final cmd in commands) {
        expect(cmd['params'], isA<List>(), reason: '${cmd['command']} params');
      }
    });

    test('human field is always a non-null map', () {
      final commands =
          (catalog['commands'] as List).cast<Map<String, dynamic>>();
      for (final cmd in commands) {
        expect(
          cmd['human'],
          isA<Map>(),
          reason: '${cmd['command']} human field',
        );
      }
    });

    test('YAML merge with empty map does not change output', () {
      final baseline = YoloitCliToolCatalog.catalogJson();
      final merged = YoloitCliToolCatalog.catalogJson({});
      // Both should have same number of commands
      final baseDecoded = jsonDecode(baseline) as Map<String, dynamic>;
      final mergedDecoded = jsonDecode(merged) as Map<String, dynamic>;
      expect(
        (mergedDecoded['commands'] as List).length,
        equals((baseDecoded['commands'] as List).length),
      );
    });

    test('YAML merge adds extra variants to matching command', () {
      // Find a command that already has variants
      final target = YoloitCliToolCatalog.tools.firstWhere(
        (t) => t.humanVariants.isNotEmpty,
      );
      final extra = <String, Map<String, List<String>>>{
        target.command: {
          'test_locale': ['__smoke_test_phrase__'],
        },
      };
      final json = YoloitCliToolCatalog.catalogJson(extra);
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      final commands = (decoded['commands'] as List).cast<Map<String, dynamic>>();
      final found = commands.firstWhere(
        (c) => c['command'] == target.command,
      );
      final human = found['human'] as Map<String, dynamic>;
      final testLocale = (human['test_locale'] as List?)?.cast<String>() ?? [];
      expect(testLocale, contains('__smoke_test_phrase__'));
    });
  });
}
