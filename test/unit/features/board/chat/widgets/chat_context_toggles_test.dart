import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_context_toggles.dart';

void main() {
  group('ChatContextToggles', () {
    testWidgets('renders all four toggles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatContextToggles(
              cliHelp: true,
              boardSnapshot: false,
              boardPanelsJson: true,
              systemPrompt: false,
              onCliHelpChanged: (_) {},
              onBoardSnapshotChanged: (_) {},
              onBoardPanelsJsonChanged: (_) {},
              onSystemPromptChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('CLI Help'), findsOneWidget);
      expect(find.text('Board Screenshot'), findsOneWidget);
      expect(find.text('Board Panels JSON'), findsOneWidget);
      expect(find.text('System Prompt'), findsOneWidget);
    });

    testWidgets('toggles CLI Help on tap', (tester) async {
      bool? newValue;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatContextToggles(
              cliHelp: true,
              boardSnapshot: false,
              boardPanelsJson: false,
              systemPrompt: false,
              onCliHelpChanged: (v) => newValue = v,
              onBoardSnapshotChanged: (_) {},
              onBoardPanelsJsonChanged: (_) {},
              onSystemPromptChanged: (_) {},
            ),
          ),
        ),
      );

      await tester.tap(find.text('CLI Help'));
      expect(newValue, false);
    });

    testWidgets('shows checked box for enabled items', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatContextToggles(
              cliHelp: true,
              boardSnapshot: false,
              boardPanelsJson: false,
              systemPrompt: false,
              onCliHelpChanged: (_) {},
              onBoardSnapshotChanged: (_) {},
              onBoardPanelsJsonChanged: (_) {},
              onSystemPromptChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.check_box), findsOneWidget);
      expect(find.byIcon(Icons.check_box_outline_blank), findsNWidgets(3));
    });
  });
}
