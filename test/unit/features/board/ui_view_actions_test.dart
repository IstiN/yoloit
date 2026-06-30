import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_actions.dart';

void main() {
  test('collectFromTree finds button onTap ids', () {
    final refs = UiViewActions.collectFromTree(<String, dynamic>{
      'type': 'column',
      'children': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'button',
          'data': 'Save',
          'onTap': 'save',
        },
        <String, dynamic>{
          'type': 'textButton',
          'label': 'Reset',
        },
      ],
    });

    expect(refs, hasLength(2));
    expect(refs.first.actionId, 'save');
    expect(refs.last.actionId, '_tap');
  });

  test('defaultScript documents action id', () {
    expect(
      UiViewActions.defaultScript('greet'),
      contains('greet'),
    );
  });
}
