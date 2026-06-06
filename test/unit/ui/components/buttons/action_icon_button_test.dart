import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/ui/components/buttons/action_icon_button.dart';

void main() {
  group('ActionIconButton', () {
    testWidgets('renders icon with correct color and size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionIconButton(
              icon: Icons.edit,
              color: Colors.red,
              tooltip: 'Edit',
              onTap: () {},
            ),
          ),
        ),
      );

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, Icons.edit);
      expect(icon.color, Colors.red);
      expect(icon.size, 14);
    });

    testWidgets('displays tooltip', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionIconButton(
              icon: Icons.delete,
              color: Colors.grey,
              tooltip: 'Delete item',
              onTap: () {},
            ),
          ),
        ),
      );

      final tooltip = tester.widget<Tooltip>(find.byType(Tooltip));
      expect(tooltip.message, 'Delete item');
    });

    testWidgets('calls onTap when tapped', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionIconButton(
              icon: Icons.add,
              color: Colors.green,
              tooltip: 'Add',
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byType(InkWell));
      expect(tapped, isTrue);
    });

    testWidgets('has correct padding', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionIconButton(
              icon: Icons.settings,
              color: Colors.blue,
              tooltip: 'Settings',
              onTap: () {},
            ),
          ),
        ),
      );

      final padding = tester.widget<Padding>(find.byType(Padding));
      expect(padding.padding, const EdgeInsets.all(4));
    });

    testWidgets('has border radius on InkWell', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ActionIconButton(
              icon: Icons.check,
              color: Colors.white,
              tooltip: 'Check',
              onTap: () {},
            ),
          ),
        ),
      );

      final inkWell = tester.widget<InkWell>(find.byType(InkWell));
      expect(inkWell.borderRadius, BorderRadius.circular(6));
    });
  });
}
