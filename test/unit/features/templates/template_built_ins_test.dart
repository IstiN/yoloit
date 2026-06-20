import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/templates/data/template_loader.dart';
import 'package:yoloit/features/templates/data/template_sources_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  group('Built-in templates', () {
    test('built-in source points to yoloit/templates and loads all templates',
        () async {
      final source = TemplateSourcesService.instance.builtInSource;
      expect(source, isNotNull,
          reason: 'yoloit/templates directory should exist in repo');
      expect(source!.type, TemplateSourceType.local);

      const loader = LocalTemplateLoader();
      final templates = await loader.load(source);
      final ids = templates.map((t) => t.id).toSet();

      expect(ids, containsAll(<String>{
        'flutter-project',
        'home-notes',
        'weekly-review',
        'trip-planner',
        'habit-tracker',
        'brainstorm',
      }));
      expect(templates.length, 6);
    });
  });
}
