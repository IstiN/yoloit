import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/widgets/chat_slash_chips.dart';

void main() {
  group('ChatSlashChips', () {
    testWidgets('returns shrink when empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSlashChips(
              commands: const [],
              onSelect: (_) {},
            ),
          ),
        ),
      );

      expect(find.byType(SizedBox), findsOneWidget);
    });

    testWidgets('renders commands and fires onSelect', (tester) async {
      ChatSlashCommand? selected;
      final commands = [
        const ChatSlashCommand(
          id: 'model',
          displayName: 'model',
          description: 'Switch AI model',
          triggers: ['/model'],
        ),
        const ChatSlashCommand(
          id: 'context',
          displayName: 'context',
          description: 'Toggle context',
          triggers: ['/context'],
        ),
      ];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatSlashChips(
              commands: commands,
              onSelect: (cmd) => selected = cmd,
            ),
          ),
        ),
      );

      expect(find.text('model'), findsOneWidget);
      expect(find.text('context'), findsOneWidget);

      await tester.tap(find.text('context'));
      expect(selected?.id, 'context');
    });
  });
}
