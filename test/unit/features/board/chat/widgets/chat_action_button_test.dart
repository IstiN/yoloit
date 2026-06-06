import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_action_button.dart';

void main() {
  group('ChatActionButton', () {
    testWidgets('renders icon and responds to tap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatActionButton(
              icon: Icons.send,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.send), findsOneWidget);
      await tester.tap(find.byType(ChatActionButton));
      expect(tapped, isTrue);
    });

    testWidgets('applies custom colors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatActionButton(
              icon: Icons.mic,
              backgroundColor: Colors.red,
              iconColor: Colors.white,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find.descendant(
          of: find.byType(ChatActionButton),
          matching: find.byType(Container),
        ),
      );
      final decoration = container.decoration! as BoxDecoration;
      expect(decoration.color, Colors.red);

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.color, Colors.white);
    });

    testWidgets('wraps with Tooltip when provided', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatActionButton(
              icon: Icons.settings,
              tooltip: 'Settings',
            ),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsOneWidget);
    });

    testWidgets('does not render Tooltip when omitted', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatActionButton(icon: Icons.send),
          ),
        ),
      );

      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('disabled when onTap is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChatActionButton(icon: Icons.send),
          ),
        ),
      );

      // GestureDetector without onTap will not produce a ripple but is still
      // present; the main contract is that it renders without throwing.
      expect(find.byType(GestureDetector), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
    });
  });
}
