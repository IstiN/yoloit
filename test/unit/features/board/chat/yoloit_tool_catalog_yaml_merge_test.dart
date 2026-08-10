import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

/// Tests for the YAML human-variant merge helpers of [YoloitCliToolCatalog]
/// (`_mergeYamlCommands` / `_parseHumanLocales`), exercised through the
/// `debugMergeYamlCommands` test seam.
void main() {
  group('YoloitCliToolCatalog.debugMergeYamlCommands', () {
    YamlList parseCommands(String yaml) {
      final doc = loadYaml(yaml) as YamlMap;
      return doc['commands'] as YamlList;
    }

    test('does nothing when commands is null', () {
      final result = <String, Map<String, List<String>>>{};
      YoloitCliToolCatalog.debugMergeYamlCommands(result, null);
      expect(result, isEmpty);
    });

    test('parses locale maps and flat lists', () {
      final result = <String, Map<String, List<String>>>{};
      YoloitCliToolCatalog.debugMergeYamlCommands(
        result,
        parseCommands('''
commands:
  - id: note
    human:
      en: [create note, make note]
      ru: [создай заметку]
  - id: flat
    human: [just flat, another]
'''),
      );
      expect(result['note']!['en'], <String>['create note', 'make note']);
      expect(result['note']!['ru'], <String>['создай заметку']);
      expect(result['flat']!['en'], <String>['just flat', 'another']);
      expect(result, hasLength(2));
    });

    test('skips commands without id or usable phrases', () {
      final result = <String, Map<String, List<String>>>{};
      YoloitCliToolCatalog.debugMergeYamlCommands(
        result,
        parseCommands('''
commands:
  - human: [no id here]
  - id: scalar
    human: 42
  - id: notlist
    human:
      en: not-a-list
'''),
      );
      expect(result, isEmpty);
    });

    test('filters non-string phrase entries', () {
      final result = <String, Map<String, List<String>>>{};
      YoloitCliToolCatalog.debugMergeYamlCommands(
        result,
        parseCommands('''
commands:
  - id: mixed
    human: [ok phrase, 42, true]
'''),
      );
      expect(result['mixed']!['en'], <String>['ok phrase']);
    });

    test('appends phrases when merging the same command twice', () {
      final result = <String, Map<String, List<String>>>{};
      YoloitCliToolCatalog.debugMergeYamlCommands(
        result,
        parseCommands('''
commands:
  - id: reload
    human:
      en: [reload app]
'''),
      );
      YoloitCliToolCatalog.debugMergeYamlCommands(
        result,
        parseCommands('''
commands:
  - id: reload
    human:
      en: [restart app]
      ru: [перезапусти]
'''),
      );
      expect(result['reload']!['en'], <String>['reload app', 'restart app']);
      expect(result['reload']!['ru'], <String>['перезапусти']);
      expect(result, hasLength(1));
    });
  });
}
