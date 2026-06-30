import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_field_registry.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_bindings.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_tree_normalizer.dart';

void main() {
  test('normalizer maps React-style types and fields', () {
    final normalized = UiViewTreeNormalizer.normalize(<String, dynamic>{
      'type': 'View',
      'backgroundColor': '#112233',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'Text',
          'content': 'Hello',
        },
        <String, dynamic>{
          'type': 'Button',
          'title': 'Go',
        },
      ],
    });

    expect(normalized['type'], 'column');
    final children = normalized['children'] as List;
    expect((children[0] as Map)['type'], 'text');
    expect((children[0] as Map)['data'], 'Hello');
    expect((children[1] as Map)['type'], 'button');
    expect((children[1] as Map)['data'], 'Go');
  });

  test('applyFieldStorage writes one key without tap increment', () {
    final next = UiViewBindings.applyFieldStorage(
      state: <String, dynamic>{'_storage': <String, dynamic>{'name': 'Old'}},
      key: 'nameInput',
      value: 'Anna',
    );
    final storage = UiViewBindings.storageFromState(next);
    expect(storage['nameInput'], 'Anna');
    expect(storage['name'], 'Old');
    expect(storage['taps'], isNull);
  });

  test('seedFieldsFromTree seeds textField id from value', () {
    final seeded = UiViewBindings.seedFieldsFromTree(
      <String, dynamic>{
        'type': 'textField',
        'id': 'nameInput',
        'value': 'Гость',
      },
      <String, dynamic>{},
    );
    expect(seeded['nameInput'], 'Гость');
  });

  test('withLiveFields overlays registry snapshot', () {
    final registry = UiViewFieldRegistry();
    registry.register('nameInput', () => 'Anna');
    final merged = UiViewBindings.withLiveFields(
      <String, dynamic>{'_storage': <String, dynamic>{'name': 'Old'}},
      registry,
    );
    final storage = UiViewBindings.storageFromState(merged);
    expect(storage['nameInput'], 'Anna');
    expect(storage['name'], 'Old');
  });

  test('applyTree hides nodes when when resolves empty', () {
    final resolved = UiViewBindings.applyTree(
      <String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'text',
            'data': 'Visible',
          },
          <String, dynamic>{
            'type': 'text',
            'data': 'Hidden',
            'when': '{{showHidden}}',
          },
        ],
      },
      <String, dynamic>{'showHidden': ''},
    );

    final children = resolved['children'] as List;
    expect(children, hasLength(1));
    expect((children.first as Map)['data'], 'Visible');
  });
}
