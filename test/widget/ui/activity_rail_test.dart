import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/ui/widgets/activity_rail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget wrap(Widget child) => MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
  );

  testWidgets('renders one button per item and fires onTap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      wrap(
        ActivityRail(
          items: [
            ActivityRailItem(
              icon: Icons.chat_bubble_outline,
              tooltip: 'Chat',
              onTap: () => taps++,
            ),
            ActivityRailItem(
              icon: Icons.folder_outlined,
              tooltip: 'Files',
              onTap: () => taps += 10,
            ),
          ],
        ),
      ),
    );

    expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
    expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    expect(find.byType(Tooltip), findsNWidgets(2));

    await tester.tap(find.byIcon(Icons.folder_outlined));
    expect(taps, 10);
  });

  testWidgets('renders a custom icon widget instead of the icon', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        ActivityRail(
          items: [
            ActivityRailItem(
              iconWidget: const Text('W', key: Key('custom-icon')),
              tooltip: 'Custom',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    expect(find.byKey(const Key('custom-icon')), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('hover highlights the rail item', (tester) async {
    await tester.pumpWidget(
      wrap(
        ActivityRail(
          items: [
            ActivityRailItem(
              icon: Icons.settings_outlined,
              tooltip: 'Settings',
              onTap: () {},
            ),
          ],
        ),
      ),
    );

    Color? containerColor() => (tester
            .widget<AnimatedContainer>(find.byType(AnimatedContainer))
            .decoration as BoxDecoration?)
        ?.color;
    expect(containerColor(), Colors.transparent);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(find.byType(MouseRegion).last));
    await tester.pump();
    expect(containerColor(), isNot(Colors.transparent));

    await gesture.moveTo(const Offset(600, 500));
    await tester.pump();
    expect(containerColor(), Colors.transparent);
  });

  testWidgets('right rail uses a left border, left rail a right border', (
    tester,
  ) async {
    Border railBorder() {
      return tester
              .widgetList<Container>(find.byType(Container))
              .map((c) => c.decoration)
              .whereType<BoxDecoration>()
              .map((d) => d.border)
              .whereType<Border>()
              .first;
    }

    await tester.pumpWidget(
      wrap(const ActivityRail(side: ActivityRailSide.right, items: [])),
    );
    expect(railBorder().left.width, 1);
    expect(railBorder().right.style, BorderStyle.none);

    await tester.pumpWidget(
      wrap(const ActivityRail(side: ActivityRailSide.left, items: [])),
    );
    expect(railBorder().right.width, 1);
    expect(railBorder().left.style, BorderStyle.none);
  });
}
