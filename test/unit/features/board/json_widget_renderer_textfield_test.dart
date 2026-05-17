import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/widgets/json_widget_renderer.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

JsonWidgetRenderer _renderer({List<String> events = const []}) {
  final captured = events as List<String>;
  return JsonWidgetRenderer(
    onEvent: (id, payload) => captured.add(id),
  );
}

void main() {
  group('JsonWidgetRenderer — textField node', () {
    testWidgets('renders a TextField', (tester) async {
      final r = _renderer();
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'hint': 'Enter city…'}),
      ));
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('shows hint text', (tester) async {
      final r = _renderer();
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'hint': 'Search here'}),
      ));
      expect(find.text('Search here'), findsOneWidget);
    });

    testWidgets('shows initial value', (tester) async {
      final r = _renderer();
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'value': 'London', 'hint': 'city'}),
      ));
      expect(find.text('London'), findsOneWidget);
    });

    testWidgets('fires onSubmit event when user submits', (tester) async {
      final events = <String>[];
      final r = _renderer(events: events);
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'value': '', 'hint': 'city', 'onSubmit': 'submit_city'}),
      ));
      await tester.enterText(find.byType(TextField), 'Tokyo');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(events, contains('submit_city'));
    });

    testWidgets('fires onChange event while typing', (tester) async {
      final events = <String>[];
      final r = _renderer(events: events);
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'value': '', 'hint': 'city', 'onChange': 'city_input_change'}),
      ));
      await tester.enterText(find.byType(TextField), 'B');
      await tester.pump();
      expect(events, contains('city_input_change'));
    });

    testWidgets('does not fire event when no action id set', (tester) async {
      final events = <String>[];
      final r = _renderer(events: events);
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'value': '', 'hint': 'city'}),
      ));
      await tester.enterText(find.byType(TextField), 'X');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      expect(events, isEmpty);
    });

    testWidgets('renders as password field when obscure=true', (tester) async {
      final r = _renderer();
      await tester.pumpWidget(_wrap(
        r.build({'type': 'textField', 'hint': 'password', 'obscure': true}),
      ));
      final tf = tester.widget<TextField>(find.byType(TextField));
      expect(tf.obscureText, isTrue);
    });
  });

  group('JsonWidgetRenderer — unknown type', () {
    testWidgets('unknown type does not throw', (tester) async {
      final r = _renderer();
      await tester.pumpWidget(_wrap(r.build({'type': 'nonExistentWidgetType'})));
      // Should render without exception — just an empty SizedBox
      expect(find.byType(SizedBox), findsWidgets);
    });
  });
}
