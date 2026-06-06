import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/cli_tools/tool_helpers.dart';

void main() {
  group('YoloitCliToolParam', () {
    test('isFlag returns true when flag is set', () {
      final param = YoloitCliToolParam(
        key: 'verbose',
        description: 'Verbose output',
        flag: '--verbose',
      );
      expect(param.isFlag, isTrue);
    });

    test('isFlag returns false when flag is null', () {
      final param = YoloitCliToolParam(
        key: 'name',
        description: 'Name value',
      );
      expect(param.isFlag, isFalse);
    });

    test('compactKey uses shortKey when available', () {
      final param = YoloitCliToolParam(
        key: 'board',
        description: 'Board id',
        shortKey: 'b',
      );
      expect(param.compactKey, 'b');
    });

    test('compactKey falls back to key when shortKey is null', () {
      final param = YoloitCliToolParam(
        key: 'panel',
        description: 'Panel id',
      );
      expect(param.compactKey, 'panel');
    });

    group('toJsonSchema', () {
      test('string kind produces string type', () {
        final param = YoloitCliToolParam(
          key: 'name',
          description: 'Name',
          kind: YoloitCliToolParamKind.string,
        );
        final schema = param.toJsonSchema();
        expect(schema['type'], 'string');
        expect(schema['description'], 'Name');
      });

      test('number kind produces number type', () {
        final param = YoloitCliToolParam(
          key: 'count',
          description: 'Count',
          kind: YoloitCliToolParamKind.number,
        );
        final schema = param.toJsonSchema();
        expect(schema['type'], 'number');
      });

      test('boolean kind produces boolean type', () {
        final param = YoloitCliToolParam(
          key: 'enabled',
          description: 'Enabled',
          kind: YoloitCliToolParamKind.boolean,
        );
        final schema = param.toJsonSchema();
        expect(schema['type'], 'boolean');
      });

      test('includes enum when enumValues is not empty', () {
        final param = YoloitCliToolParam(
          key: 'type',
          description: 'Type',
          enumValues: ['a', 'b'],
        );
        final schema = param.toJsonSchema();
        expect(schema['enum'], ['a', 'b']);
      });

      test('omits enum when enumValues is empty', () {
        final param = YoloitCliToolParam(
          key: 'type',
          description: 'Type',
        );
        final schema = param.toJsonSchema();
        expect(schema.containsKey('enum'), isFalse);
      });
    });

    group('toCompactJsonSchema', () {
      test('omits description', () {
        final param = YoloitCliToolParam(
          key: 'name',
          description: 'Name',
        );
        final schema = param.toCompactJsonSchema();
        expect(schema.containsKey('description'), isFalse);
      });

      test('includes type', () {
        final param = YoloitCliToolParam(
          key: 'count',
          description: 'Count',
          kind: YoloitCliToolParamKind.number,
        );
        final schema = param.toCompactJsonSchema();
        expect(schema['type'], 'number');
      });
    });
  });

  group('toolParam helper', () {
    test('creates param with all fields', () {
      final param = toolParam(
        'myKey',
        'My description',
        required: true,
        flag: '--myKey',
        kind: YoloitCliToolParamKind.boolean,
        aliases: ['k', 'key'],
        runtimeDefault: YoloitCliRuntimeDefault.board,
        enumValues: ['a', 'b'],
        shortKey: 'm',
      );

      expect(param.key, 'myKey');
      expect(param.description, 'My description');
      expect(param.required, isTrue);
      expect(param.flag, '--myKey');
      expect(param.kind, YoloitCliToolParamKind.boolean);
      expect(param.aliases, ['k', 'key']);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.board);
      expect(param.enumValues, ['a', 'b']);
      expect(param.shortKey, 'm');
    });

    test('uses defaults for optional fields', () {
      final param = toolParam('key', 'desc');

      expect(param.required, isFalse);
      expect(param.flag, isNull);
      expect(param.kind, YoloitCliToolParamKind.string);
      expect(param.aliases, isEmpty);
      expect(param.runtimeDefault, isNull);
      expect(param.enumValues, isEmpty);
      expect(param.shortKey, isNull);
    });
  });

  group('boardParam helper', () {
    test('returns param with correct defaults', () {
      final param = boardParam();

      expect(param.key, 'board');
      expect(param.required, isTrue);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.board);
      expect(param.shortKey, 'b');
      expect(param.aliases, contains('board_id'));
      expect(param.aliases, contains('board_name'));
    });

    test('allows custom key', () {
      final param = boardParam('myBoard');
      expect(param.key, 'myBoard');
    });
  });

  group('panelParam helper', () {
    test('returns param with correct defaults', () {
      final param = panelParam();

      expect(param.key, 'panel');
      expect(param.required, isTrue);
      expect(param.runtimeDefault, YoloitCliRuntimeDefault.panel);
      expect(param.shortKey, 'p');
      expect(param.aliases, contains('panel_id'));
    });

    test('allows custom key', () {
      final param = panelParam('myPanel');
      expect(param.key, 'myPanel');
    });
  });

  group('panelTypeParam helper', () {
    test('returns param with required type', () {
      final param = panelTypeParam();

      expect(param.key, 'type');
      expect(param.required, isTrue);
      expect(param.shortKey, 'tp');
    });

    test('includes all panel type enum values', () {
      final param = panelTypeParam();

      expect(param.enumValues, contains('board.chat'));
      expect(param.enumValues, contains('board.terminal'));
      expect(param.enumValues, contains('board.note.markdown'));
      expect(param.enumValues, contains('board.kanban'));
      expect(param.enumValues, contains('board.widget.custom'));
      expect(param.enumValues.length, 18);
    });

    test('aliases include panel_type and kind', () {
      final param = panelTypeParam();
      expect(param.aliases, contains('panel_type'));
      expect(param.aliases, contains('kind'));
    });
  });
}
