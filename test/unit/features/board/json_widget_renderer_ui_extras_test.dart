import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

void main() {
  testWidgets('listTile and scroll aliases render', (tester) async {
    final renderer = JsonWidgetRenderer(onEvent: _noop);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderer.build(<String, dynamic>{
            'type': 'scroll',
            'child': <String, dynamic>{
              'type': 'column',
              'children': <Map<String, dynamic>>[
                <String, dynamic>{
                  'type': 'listTile',
                  'title': 'Item',
                  'subtitle': 'Details',
                  'onTap': 'open',
                },
                <String, dynamic>{
                  'type': 'markdown',
                  'data': '**bold**',
                },
              ],
            },
          }),
        ),
      ),
    );

    expect(find.text('Item'), findsOneWidget);
    expect(find.text('Details'), findsOneWidget);
    expect(find.textContaining('bold'), findsOneWidget);
  });

  testWidgets('unknown type shows placeholder', (tester) async {
    final renderer = JsonWidgetRenderer(onEvent: _noop);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderer.build(<String, dynamic>{
            'type': 'totallyUnknownWidget',
          }),
        ),
      ),
    );

    expect(find.textContaining('Unknown type'), findsOneWidget);
  });
}

void _noop(String actionId, Map<String, dynamic> payload) {}
