import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/widgets/bouncing_dots_indicator.dart';

void main() {
  group('BouncingDotsIndicator', () {
    testWidgets('renders three dots', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BouncingDotsIndicator()),
      );

      expect(find.byType(Container), findsNWidgets(3));
    });

    testWidgets('dots are circular', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BouncingDotsIndicator()),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.shape, BoxShape.circle);
      }
    });

    testWidgets('uses provided color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: BouncingDotsIndicator(color: Colors.red),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, Colors.red);
      }
    });

    testWidgets('uses theme color when no color provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: const BouncingDotsIndicator(),
        ),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      final decoration = containers.first.decoration! as BoxDecoration;
      expect(decoration.color, isNotNull);
    });

    testWidgets('dots have correct dimensions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BouncingDotsIndicator()),
      );

      final containers = tester.widgetList<Container>(find.byType(Container));
      for (final container in containers) {
        expect(container.constraints!.minWidth, 5);
        expect(container.constraints!.minHeight, 5);
      }
    });

    testWidgets('has padding between dots', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: BouncingDotsIndicator()),
      );

      final paddings = tester.widgetList<Padding>(find.byType(Padding));
      expect(paddings.length, greaterThanOrEqualTo(3));
    });
  });
}
