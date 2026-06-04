import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/feedback/status_badge.dart';

void main() {
  group('StatusBadge', () {
    testWidgets('renders label with default styling', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StatusBadge(label: 'Active', color: Colors.green),
        ),
      );

      expect(find.text('Active'), findsOneWidget);

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(6));

      final text = tester.widget<Text>(find.text('Active'));
      expect(text.style?.fontSize, 11);
      expect(text.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('applies custom parameters', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: StatusBadge(
            label: 'Done',
            color: Colors.blue,
            borderRadius: 4,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            backgroundAlpha: 40,
            borderAlpha: 90,
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(4));
      expect(container.padding, const EdgeInsets.symmetric(horizontal: 12, vertical: 6));

      final text = tester.widget<Text>(find.text('Done'));
      expect(text.style?.fontSize, 10);
      expect(text.style?.fontWeight, FontWeight.w600);
    });
  });
}
