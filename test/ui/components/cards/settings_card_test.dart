import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/cards/settings_card.dart';

void main() {
  group('SettingsCard', () {
    testWidgets('renders with default padding and border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return SettingsCard(
                  child: const Text('Hello'),
                );
              },
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(14));
      expect(container.margin, isNull);

      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.borderRadius, BorderRadius.circular(10));
    });

    testWidgets('applies custom borderColor and margin', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return SettingsCard(
                  borderColor: Colors.red,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.zero,
                  child: const Text('Custom'),
                );
              },
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.margin, const EdgeInsets.only(bottom: 8));
      expect(container.padding, EdgeInsets.zero);
    });
  });
}
