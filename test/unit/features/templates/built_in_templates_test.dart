import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  group('Built-in templates', () {
    test('all templates in yoloit/templates load without errors', () async {
      final root = Directory('yoloit/templates');
      expect(root.existsSync(), isTrue);

      final source = TemplateSource(
        id: 'builtins',
        type: TemplateSourceType.local,
        localPath: root.path,
      );
      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);

      final expectedIds = <String>{
        'flutter-project',
        'home-notes',
        'weekly-review',
        'trip-planner',
        'habit-tracker',
        'brainstorm',
      };
      final loadedIds = templates.map((t) => t.id).toSet();
      expect(loadedIds, containsAll(expectedIds));

      for (final template in templates) {
        expect(template.id, isNotEmpty);
        expect(template.name, isNotEmpty);
        expect(template.operations, isNotEmpty);
      }
    });
  });
}
