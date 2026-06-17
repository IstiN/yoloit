import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/utils/panel_scroll_memory.dart';

void main() {
  test('read and write roundtrip scroll offset in panel state', () {
    const state = <String, dynamic>{'markdown': '# hi'};
    final updated = PanelScrollMemory.write(state, 128.5);

    expect(PanelScrollMemory.read(state), isNull);
    expect(PanelScrollMemory.read(updated), 128.5);
    expect(updated['markdown'], '# hi');
  });

  testWidgets('restoreAfterLayout jumps to saved offset', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            controller: controller,
            child: Column(
              children: List.generate(
                40,
                (index) => SizedBox(height: 40, child: Text('$index')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    PanelScrollMemory.restoreAfterLayout(controller, offset: 200);
    await tester.pump();

    expect(controller.offset, closeTo(200, 1));
    expect(
      controller.offset,
      lessThanOrEqualTo(controller.position.maxScrollExtent),
    );
  });
}
