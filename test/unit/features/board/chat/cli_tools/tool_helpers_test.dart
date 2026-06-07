import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';

void main() {
  group('YoloitCliToolParam', () {
    test('creates with default values', () {
      const param = YoloitCliToolParam(
        key: 'name',
        description: 'A name parameter',
      );

      expect(param.key, 'name');
      expect(param.description, 'A name parameter');
      expect(param.required, false);
      expect(param.flag, isNull);
      expect(param.kind, YoloitCliToolParamKind.string);
      expect(param.aliases, isEmpty);
      expect(param.runtimeDefault, isNull);
      expect(param.enumValues, isEmpty);
      expect(param.shortKey, isNull);
    });

    test('isFlag returns true when flag is set', () {
      const param = YoloitCliToolParam(
        key: 'verbose',
        description: 'Verbose mode',
        flag: '--verbose',
      );
      expect(param.isFlag, true);
    });

    test('isFlag returns false when flag is null', () {
      const param = YoloitCliToolParam(
        key: 'name',
        description: 'Name',
      );
      expect(param.isFlag, false);
    });

    test('compactKey returns shortKey when available', () {
      const param = YoloitCliToolParam(
        key: 'board',
        description: 'Board',
        shortKey: 'b',
      );
      expect(param.compactKey, 'b');
    });

    test('compactKey falls back to key', () {
      const param = YoloitCliToolParam(
        key: 'name',
        description: 'Name',
      );
      expect(param.compactKey, 'name');
    });

    test('toJsonSchema includes enum when present', () {
      const param = YoloitCliToolParam(
        key: 'type',
        description: 'Panel type',
        kind: YoloitCliToolParamKind.string,
        enumValues: ['a', 'b'],
      );

      final schema = param.toJsonSchema();
      expect(schema['type'], 'string');
      expect(schema['description'], 'Panel type');
      expect(schema['enum'], ['a', 'b']);
    });

    test('toJsonSchema omits enum when empty', () {
      const param = YoloitCliToolParam(
        key: 'name',
        description: 'Name',
      );

      final schema = param.toJsonSchema();
      expect(schema.containsKey('enum'), false);
    });

    test('toJsonSchema handles number kind', () {
      const param = YoloitCliToolParam(
        key: 'count',
        description: 'Count',
        kind: YoloitCliToolParamKind.number,
      );

      final schema = param.toJsonSchema();
      expect(schema['type'], 'number');
    });

    test('toJsonSchema handles boolean kind', () {
      const param = YoloitCliToolParam(
        key: 'enabled',
        description: 'Enabled',
        kind: YoloitCliToolParamKind.boolean,
      );

      final schema = param.toJsonSchema();
      expect(schema['type'], 'boolean');
    });

    test('toCompactJsonSchema omits description', () {
      const param = YoloitCliToolParam(
        key: 'type',
        description: 'Panel type',
        enumValues: ['a', 'b'],
      );

      final schema = param.toCompactJsonSchema();
      expect(schema.containsKey('description'), false);
      expect(schema['type'], 'string');
      expect(schema['enum'], ['a', 'b']);
    });
  });

  group('toolParam factory', () {
    test('creates param with all fields', () {
      final param = toolParam(
        'model',
        'Model ID',
        required: true,
        flag: '--model',
        kind: YoloitCliToolParamKind.string,
        aliases: const ['m'],
        runtimeDefault: YoloitCliRuntimeDefault.panel,
        enumValues: const ['gpt-4', 'claude'],
        shortKey: 'mid',
      );

      expect(param.key, 'model');
      expect(param.description, 'Model ID');
      expect(param.required, true);
      expect(param.flag, '--model');
      expect(param.kind, YoloitCliToolParamKind.string);
      expect(param.aliases, ['m']);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.panel);
      expect(param.enumValues, ['gpt-4', 'claude']);
      expect(param.shortKey, 'mid');
    });
  });

  group('boardParam', () {
    test('creates board parameter with correct defaults', () {
      final param = boardParam();

      expect(param.key, 'board');
      expect(param.required, true);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.board);
      expect(param.shortKey, 'b');
      expect(param.aliases, contains('board_id'));
      expect(param.aliases, contains('board_name'));
    });

    test('accepts custom key', () {
      final param = boardParam('target_board');
      expect(param.key, 'target_board');
    });
  });

  group('panelParam', () {
    test('creates panel parameter with correct defaults', () {
      final param = panelParam();

      expect(param.key, 'panel');
      expect(param.required, true);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.panel);
      expect(param.shortKey, 'p');
      expect(param.aliases, contains('panel_id'));
      expect(param.aliases, contains('panel_title'));
    });
  });

  group('modelIdParam', () {
    test('creates model_id parameter', () {
      final param = modelIdParam();

      expect(param.key, 'model_id');
      expect(param.required, true);
      expect(param.shortKey, 'mid');
      expect(param.aliases, contains('id'));
    });

    test('can be optional', () {
      final param = modelIdParam(required: false);
      expect(param.required, false);
    });
  });

  group('boardFlagParam', () {
    test('creates board flag parameter', () {
      final param = boardFlagParam();

      expect(param.key, 'board');
      expect(param.flag, '--board');
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.board);
      expect(param.shortKey, 'b');
      expect(param.required, false);
    });
  });

  group('panelFlagParam', () {
    test('creates panel flag parameter', () {
      final param = panelFlagParam();

      expect(param.key, 'panel');
      expect(param.flag, '--panel');
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.panel);
      expect(param.shortKey, 'p');
      expect(param.required, false);
    });
  });

  group('panelTypeParam', () {
    test('creates panel type parameter with all enum values', () {
      final param = panelTypeParam();

      expect(param.key, 'type');
      expect(param.required, true);
      expect(param.shortKey, 'tp');
      expect(param.enumValues, isNotEmpty);
      expect(param.enumValues, contains('board.chat'));
      expect(param.enumValues, contains('board.terminal'));
      expect(param.enumValues, contains('board.note.markdown'));
    });
  });
}
