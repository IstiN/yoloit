import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/templates/data/template_service.dart';
import 'package:yoloit/features/templates/model/template_models.dart';

void main() {
  group('BoardTemplateService', () {
    final service = BoardTemplateService();

    const flutterTemplate = BoardTemplate(
      id: 'flutter-project',
      name: 'Flutter Development',
      sourceId: 'test',
      parameters: [
        TemplateParameter(
          name: 'projectName',
          type: TemplateParameterType.string,
          label: 'Project Name',
          required: true,
          defaultValue: 'My App',
        ),
        TemplateParameter(
          name: 'projectPath',
          type: TemplateParameterType.path,
          label: 'Project Path',
          required: true,
          picker: TemplateParameterPicker.directory,
        ),
        TemplateParameter(
          name: 'includeKanban',
          type: TemplateParameterType.boolean,
          label: 'Include Kanban',
          defaultValue: true,
        ),
        TemplateParameter(
          name: 'flutterCommand',
          type: TemplateParameterType.choice,
          label: 'Flutter Command',
          defaultValue: 'flutter run',
          options: [
            TemplateParameterOption(value: 'flutter run', label: 'Run'),
            TemplateParameterOption(value: 'flutter test', label: 'Test'),
          ],
        ),
      ],
      operations: [
        TemplateOperation(
          payload: {
            'op': 'panel.create',
            'type': 'board.filetree',
            'title': 'Files: {{projectName}}',
            'state': {'rootPath': '{{projectPath}}'},
          },
        ),
        TemplateOperation(
          condition: '{{includeKanban}}',
          payload: {
            'op': 'panel.create',
            'type': 'board.kanban',
            'title': 'Kanban: {{projectName}}',
          },
        ),
      ],
    );

    test('buildEffectiveParameters fills defaults', () {
      final params = service.buildEffectiveParameters(
        flutterTemplate,
        {'projectPath': '/home/user/app'},
      );
      expect(params['projectName'], 'My App');
      expect(params['projectPath'], '/home/user/app');
      expect(params['includeKanban'], true);
      expect(params['flutterCommand'], 'flutter run');
    });

    test('buildOperations interpolates parameters and respects conditions', () {
      final ops = service.buildOperations(
        flutterTemplate,
        {
          'projectName': 'Shop',
          'projectPath': '/projects/shop',
          'includeKanban': 'false',
        },
      );
      expect(ops.length, 1);
      expect(ops.first['title'], 'Files: Shop');
      expect(ops.first['state']['rootPath'], '/projects/shop');
    });

    test('validateParameters reports missing required values', () {
      final errors = service.validateParameters(
        flutterTemplate,
        {'projectName': 'Shop'},
      );
      expect(errors.containsKey('projectPath'), isTrue);
      expect(errors.containsKey('projectName'), isFalse);
    });

    test('validateParameters accepts valid choice values', () {
      final errors = service.validateParameters(
        flutterTemplate,
        {
          'projectName': 'Shop',
          'projectPath': '/projects/shop',
          'flutterCommand': 'flutter test',
        },
      );
      expect(errors['flutterCommand'], isNull);
    });

    test('validateParameters rejects invalid choice values', () {
      final errors = service.validateParameters(
        flutterTemplate,
        {
          'projectName': 'Shop',
          'projectPath': '/projects/shop',
          'flutterCommand': 'flutter build',
        },
      );
      expect(errors['flutterCommand'], 'Invalid option');
    });
  });
}
