import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_empty_state.dart';

void main() {
  group('ChatEmptyState', () {
    testWidgets('renders icon and text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChatEmptyState()),
        ),
      );

      expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      expect(find.text('Send a message to start'), findsOneWidget);
    });

    testWidgets('icon has expected size and color', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ChatEmptyState()),
        ),
      );

      final icon = tester.widget<Icon>(find.byIcon(Icons.chat_bubble_outline));
      expect(icon.size, 40);
      expect(icon.color, isA<Color>());
    });
  });
}
