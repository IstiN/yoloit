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

  group('collectFromTree collectability rules', () {
    List<UiViewActionRef> collectNode(Map<String, dynamic> node) =>
        UiViewActions.collectFromTree(node);

    test('collects button-family types without any handler', () {
      final refs = UiViewActions.collectFromTree(<String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'button'},
          <String, dynamic>{'type': 'textButton'},
          <String, dynamic>{'type': 'outlinedButton'},
          <String, dynamic>{'type': 'iconButton'},
          <String, dynamic>{'type': 'chip'},
        ],
      });

      expect(refs, hasLength(5));
      expect(refs.map((r) => r.actionId), everyElement('_tap'));
    });

    test('skips handler-less interactive types that need a handler', () {
      final refs = UiViewActions.collectFromTree(<String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{'type': 'gestureDetector'},
          <String, dynamic>{'type': 'chart'},
          <String, dynamic>{'type': 'listTile'},
          <String, dynamic>{'type': 'inkWell'},
          <String, dynamic>{'type': 'switch'},
          <String, dynamic>{'type': 'checkbox'},
          <String, dynamic>{'type': 'slider'},
          <String, dynamic>{'type': 'dropdown'},
          <String, dynamic>{'type': 'textField'},
        ],
      });

      expect(refs, isEmpty);
    });

    test('collects interactive types carrying any supported handler', () {
      final cases = <Map<String, dynamic>>[
        <String, dynamic>{'type': 'gestureDetector', 'onTap': 'tap'},
        <String, dynamic>{'type': 'chart', 'onTap': 'chartTap'},
        <String, dynamic>{'type': 'listTile', 'onTap': 'tileTap'},
        <String, dynamic>{'type': 'inkWell', 'onTap': 'inkTap'},
        <String, dynamic>{'type': 'switch', 'onChanged': 'toggle'},
        <String, dynamic>{'type': 'checkbox', 'onChanged': 'check'},
        <String, dynamic>{'type': 'slider', 'onChange': 'slide'},
        <String, dynamic>{'type': 'dropdown', 'onChange': 'pick'},
        <String, dynamic>{'type': 'textField', 'onSubmit': 'submit'},
        <String, dynamic>{'type': 'textField', 'onChange': 'edit'},
        <String, dynamic>{'type': 'gestureDetector', 'onPress': 'press'},
      ];

      final refs = UiViewActions.collectFromTree(<String, dynamic>{
        'type': 'column',
        'children': cases,
      });

      expect(refs, hasLength(cases.length));
      expect(
        refs.map((r) => r.actionId),
        [
          'tap',
          'chartTap',
          'tileTap',
          'inkTap',
          'toggle',
          'check',
          'slide',
          'pick',
          'submit',
          'edit',
          'press',
        ],
      );
    });

    test('skips non-interactive types even when they carry a handler', () {
      expect(
        collectNode(<String, dynamic>{'type': 'container', 'onTap': 'tap'}),
        isEmpty,
      );
      expect(
        collectNode(<String, dynamic>{'type': 'text', 'onTap': 'tap'}),
        isEmpty,
      );
      expect(
        collectNode(<String, dynamic>{'onTap': 'tap'}),
        isEmpty,
      );
    });

    test('walks both children lists and single child nodes', () {
      final refs = UiViewActions.collectFromTree(<String, dynamic>{
        'type': 'column',
        'children': <Map<String, dynamic>>[
          <String, dynamic>{
            'type': 'container',
            'child': <String, dynamic>{
              'type': 'button',
              'data': 'Nested',
            },
          },
        ],
        'child': <String, dynamic>{
          'type': 'textButton',
          'label': 'Root child',
        },
      });

      expect(refs, hasLength(2));
      expect(refs.map((r) => r.label), containsAll(['Nested', 'Root child']));
    });

    test('ignores non-map nodes in children', () {
      final refs = UiViewActions.collectFromTree(<String, dynamic>{
        'type': 'column',
        'children': <dynamic>[
          'a string',
          42,
          <String, dynamic>{'type': 'button'},
        ],
      });

      expect(refs, hasLength(1));
    });
  });

  group('uniqueActionIds', () {
    test('deduplicates ids preserving first-seen order', () {
      const refs = [
        UiViewActionRef(actionId: 'a', nodeType: 'button'),
        UiViewActionRef(actionId: 'b', nodeType: 'button'),
        UiViewActionRef(actionId: 'a', nodeType: 'chip'),
      ];

      expect(UiViewActions.uniqueActionIds(refs), ['a', 'b']);
    });
  });
}
