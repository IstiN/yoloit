import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  group('LocalTemplateLoader', () {
    late Directory tempDir;
    late TemplateSource source;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('templates_test_');
      source = TemplateSource(
        id: 'local-test',
        type: TemplateSourceType.local,
        localPath: tempDir.path,
      );
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    Future<void> _writeTemplate(
      String dirName,
      String yamlContent,
    ) async {
      final dir = Directory(p.join(tempDir.path, dirName));
      await dir.create(recursive: true);
      await File(p.join(dir.path, 'template.yaml')).writeAsString(yamlContent);
    }

    test('loads templates from subdirectories', () async {
      await _writeTemplate('flutter', '''
id: flutter-test
name: Flutter Test
parameters:
  - name: projectPath
    type: path
    label: Path
operations:
  - op: panel.create
    type: board.filetree
    title: "Files"
    state:
      rootPath: "{{projectPath}}"
''');
      await _writeTemplate('empty', 'not a valid yaml map');

      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);
      expect(templates.length, 1);
      expect(templates.first.id, 'flutter-test');
      expect(templates.first.parameters.length, 1);
      expect(templates.first.operations.length, 1);
    });

    test('returns empty list for missing directory', () async {
      final missingSource = TemplateSource(
        id: 'missing',
        type: TemplateSourceType.local,
        localPath: '/non/existent/path',
      );
      const loader = LocalTemplateLoader();
      final templates = await loader.load(missingSource);
      expect(templates, isEmpty);
    });

    test('converts YAML state to plain JSON-serializable values', () async {
      await _writeTemplate('rich', '''
id: rich-test
name: Rich Test
operations:
  - op: panel.create
    type: board.kanban
    state:
      columns: [Todo, Done]
      cards:
        - title: Card 1
          column: Todo
''');

      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);
      expect(templates.length, 1);

      final state = templates.first.operations.first.payload['state']
          as Map<String, dynamic>;
      // Should not contain any YamlScalar / YamlList wrappers.
      expect(() => jsonEncode(state), returnsNormally);
      expect(state['columns'], ['Todo', 'Done']);
      expect(state['cards'], isA<List<dynamic>>());
      expect((state['cards'] as List).first['title'], 'Card 1');
    });
  });
}
