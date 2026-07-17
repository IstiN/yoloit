import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

void main() {
  testWidgets('button without onTap stays enabled and shows label', (
    tester,
  ) async {
    const renderer = JsonWidgetRenderer(onEvent: _noop);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderer.build(<String, dynamic>{
            'type': 'button',
            'data': 'Фиолетовая',
            'style': <String, dynamic>{
              'backgroundColor': '#800080',
              'color': 'white',
            },
          }),
        ),
      ),
    );

    expect(find.text('Фиолетовая'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(button.onPressed, isNotNull);
  });
}

void _noop(String actionId, Map<String, dynamic> payload) {}
