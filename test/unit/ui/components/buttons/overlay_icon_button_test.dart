import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/buttons/overlay_icon_button.dart';

void main() {
  group('OverlayIconButton', () {
    testWidgets('renders icon with tooltip in default mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.edit,
              tooltip: 'Edit',
              onTap: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byTooltip('Edit'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.add,
              tooltip: 'Add',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('applies active background color when active', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.star,
              tooltip: 'Star',
              onTap: () {},
              active: true,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);
      expect(decoration.color, isNot(Colors.transparent));
    });

    testWidgets('mini mode has no padding and no border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: () {},
              mini: true,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, EdgeInsets.zero);

      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNull);
    });

    testWidgets('non-mini mode has padding and border', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.menu,
              tooltip: 'Menu',
              onTap: () {},
              mini: false,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byType(Container));
      expect(container.padding, const EdgeInsets.all(8));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNotNull);
    });

    testWidgets('uses 14px icon size in mini mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.close,
              tooltip: 'Close',
              onTap: () {},
              mini: true,
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 14);
    });

    testWidgets('uses 15px icon size in default mode', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OverlayIconButton(
              icon: Icons.menu,
              tooltip: 'Menu',
              onTap: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.size, 15);
    });
  });
}
