import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/input/panel_text_controller_mixin.dart';

class _TestWidget extends StatefulWidget {
  const _TestWidget({required this.text});
  final String text;

  @override
  State<_TestWidget> createState() => _TestWidgetState();
}

class _TestWidgetState extends State<_TestWidget>
    with PanelTextControllerMixin<_TestWidget> {
  @override
  String get panelText => widget.text;

  @override
  Widget build(BuildContext context) => Container();
}

void main() {
  group('PanelTextControllerMixin', () {
    testWidgets('initialises controller with panelText', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _TestWidget(text: 'hello')),
      );

      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      expect(state.controller.text, 'hello');
    });

    testWidgets('syncs controller when panelText changes', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _TestWidget(text: 'initial')),
      );

      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      expect(state.controller.text, 'initial');

      await tester.pumpWidget(
        const MaterialApp(home: _TestWidget(text: 'updated')),
      );
      await tester.pump();

      expect(state.controller.text, 'updated');
      expect(
        state.controller.selection,
        const TextSelection.collapsed(offset: 7),
      );
    });

    testWidgets(
      'does not touch controller when panelText already matches',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: _TestWidget(text: 'same')),
        );

        final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
        // Manually move cursor to middle
        state.controller.selection = const TextSelection.collapsed(offset: 2);

        await tester.pumpWidget(
          const MaterialApp(home: _TestWidget(text: 'same')),
        );
        await tester.pump();

        expect(state.controller.text, 'same');
        expect(
          state.controller.selection,
          const TextSelection.collapsed(offset: 2),
        );
      },
    );

    testWidgets('disposes controller on unmount', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: _TestWidget(text: 'x')),
      );

      final state = tester.state<_TestWidgetState>(find.byType(_TestWidget));
      expect(state.controller, isNotNull);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));

      // After dispose, accessing text should not throw but the mixin
      // disposed it; we just verify no leak by checking pump completes.
      expect(tester.takeException(), isNull);
    });
  });
}
