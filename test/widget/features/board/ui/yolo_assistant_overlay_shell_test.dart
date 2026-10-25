import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/ui/yolo_assistant_overlay_shell.dart';

YoloAssistantOverlayShell _shell({
  required bool expanded,
  BoxBorder? border,
}) {
  return YoloAssistantOverlayShell(
    expanded: expanded,
    badgeSize: 42,
    expandedWidth: 320,
    expandedHeight: 220,
    badgeIcon: const Text('Badge'),
    headerTrailing: const Text('Action'),
    content: const Text('Conversation'),
    border: border,
    duration: Duration.zero,
  );
}

Widget _app(Widget child) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  testWidgets('collapsed shell derives its size from unbounded constraints', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(UnconstrainedBox(child: _shell(expanded: false))),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AnimatedContainer)),
      const Size(42, 42),
    );
    expect(find.text('Badge'), findsOneWidget);
    expect(find.text('Conversation'), findsNothing);
  });

  testWidgets('expanded shell uses configured dimensions and expanded content', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        UnconstrainedBox(
          child: _shell(
            expanded: true,
            border: Border.all(color: Colors.white),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AnimatedContainer)),
      const Size(320, 220),
    );
    expect(find.text('YOLO'), findsOneWidget);
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Conversation'), findsOneWidget);
    expect(find.text('Badge'), findsNothing);
  });

  testWidgets('bounded parent constraints take precedence over configured size', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        SizedBox(
          width: 240,
          height: 180,
          child: _shell(expanded: false),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(AnimatedContainer)),
      const Size(240, 180),
    );
  });
}
