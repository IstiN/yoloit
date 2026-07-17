import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';

void main() {
  testWidgets('svg node renders full markup', (tester) async {
    const renderer = JsonWidgetRenderer(onEvent: _noop);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderer.build(<String, dynamic>{
            'type': 'svg',
            'width': 40,
            'height': 40,
            'data':
                '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
                '<circle cx="5" cy="5" r="4" fill="#800080"/></svg>',
          }),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('svg node wraps bare path shorthand', (tester) async {
    const renderer = JsonWidgetRenderer(onEvent: _noop);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: renderer.build(<String, dynamic>{
            'type': 'svg',
            'path':
                'M 50 10 a 40,40 0 1,0 80,0 a 40,40 0 1,0 -80,0 Z',
            'fill': '#FF5733',
            'width': 32,
            'height': 32,
          }),
        ),
      ),
    );

    expect(find.byType(SvgPicture), findsOneWidget);
  });
}

void _noop(String actionId, Map<String, dynamic> payload) {}
