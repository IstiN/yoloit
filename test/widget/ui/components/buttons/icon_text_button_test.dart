import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/ui/components/buttons/icon_text_button.dart';

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('inactive button responds to hover and tap', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _app(
        IconTextButton(
          label: 'Documentation',
          icon: Icons.description_outlined,
          onTap: () => taps++,
        ),
      ),
    );

    final button = tester.widget<IconTextButton>(
      find.byType(IconTextButton),
    );
    Text label() => tester.widget<Text>(find.text('Documentation'));
    BoxDecoration decoration() =>
        tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration!
            as BoxDecoration;

    expect(label().style?.color, button.color);
    expect(label().style?.fontWeight, FontWeight.w400);
    expect(decoration().color, Colors.transparent);
    expect(find.byIcon(Icons.description_outlined), findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(IconTextButton)));
    await tester.pump();

    expect(label().style?.color, button.color.withAlpha(200));
    expect(decoration().color, isNot(Colors.transparent));

    await mouse.moveTo(Offset.zero);
    await tester.pump();
    expect(label().style?.color, button.color);
    expect(decoration().color, Colors.transparent);

    await tester.tap(find.byType(IconTextButton));
    expect(taps, 1);
  });

  testWidgets('active dense button uses its override accent without an icon', (
    tester,
  ) async {
    const activeColor = Colors.orange;
    await tester.pumpWidget(
      _app(
        const IconTextButton(
          label: 'Selected',
          activeColor: activeColor,
          isActive: true,
          dense: true,
        ),
      ),
    );

    final label = tester.widget<Text>(find.text('Selected'));
    expect(label.style?.color, activeColor);
    expect(label.style?.fontWeight, FontWeight.w600);
    expect(find.byType(Icon), findsNothing);

    final container = tester.widget<AnimatedContainer>(
      find.byType(AnimatedContainer),
    );
    expect(
      container.padding,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.color, activeColor.withAlpha(30));
  });
}
