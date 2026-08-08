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

  group('BoardTemplateService parameter validation rules', () {
    final service = BoardTemplateService();

    BoardTemplate templateWith(TemplateParameter param) => BoardTemplate(
      id: 'validation-template',
      name: 'Validation',
      sourceId: 'test',
      parameters: [param],
    );

    const validatedParam = TemplateParameter(
      name: 'title',
      type: TemplateParameterType.string,
      label: 'Title',
      validation: TemplateParameterValidation(
        minLength: 3,
        maxLength: 5,
        pattern: r'^[a-z]+$',
      ),
    );

    test('accepts a value that satisfies every rule', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': 'abc'},
      );
      expect(errors, isEmpty);
    });

    test('reports values shorter than minLength', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': 'ab'},
      );
      expect(errors['title'], 'Minimum length is 3');
    });

    test('reports values longer than maxLength', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': 'abcdef'},
      );
      expect(errors['title'], 'Maximum length is 5');
    });

    test('reports values that do not match the pattern', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': 'abc1'},
      );
      expect(errors['title'], 'Invalid format');
    });

    test('minLength takes precedence over pattern violations', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': 'A1'},
      );
      expect(errors['title'], 'Minimum length is 3');
    });

    test('ignores an empty pattern', () {
      const param = TemplateParameter(
        name: 'title',
        type: TemplateParameterType.string,
        label: 'Title',
        validation: TemplateParameterValidation(pattern: ''),
      );
      final errors = service.validateParameters(
        templateWith(param),
        {'title': 'anything goes'},
      );
      expect(errors, isEmpty);
    });

    test('accepts any value when no validation is configured', () {
      const param = TemplateParameter(
        name: 'title',
        type: TemplateParameterType.string,
        label: 'Title',
      );
      final errors = service.validateParameters(
        templateWith(param),
        {'title': 'x'},
      );
      expect(errors, isEmpty);
    });

    test('skips validation for empty optional values', () {
      final errors = service.validateParameters(
        templateWith(validatedParam),
        {'title': ''},
      );
      expect(errors, isEmpty);
    });

    test('requires a value before running validation rules', () {
      const requiredParam = TemplateParameter(
        name: 'title',
        type: TemplateParameterType.string,
        label: 'Title',
        required: true,
        validation: TemplateParameterValidation(minLength: 3),
      );
      final errors = service.validateParameters(
        templateWith(requiredParam),
        {'title': ''},
      );
      expect(errors['title'], 'Required');
    });

    test('accepts boundary lengths exactly at min and max', () {
      expect(
        service.validateParameters(
          templateWith(validatedParam),
          {'title': 'abc'},
        ),
        isEmpty,
      );
      expect(
        service.validateParameters(
          templateWith(validatedParam),
          {'title': 'abcde'},
        ),
        isEmpty,
      );
    });
  });
}
