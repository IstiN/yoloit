import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/ui/widgets/yolo_badge_chat_shell.dart';

void main() {
  group('YoloBadgeChatShell', () {
    Widget shell({
      required bool isOpen,
      required VoidCallback onToggle,
      required Widget panelContent,
    }) {
      return MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 800,
            height: 600,
            child: YoloBadgeChatShell(
              isOpen: isOpen,
              onToggle: onToggle,
              panelContent: panelContent,
            ),
          ),
        ),
      );
    }

    testWidgets('shows YOLO tab when closed', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        shell(
          isOpen: false,
          onToggle: () => toggled = true,
          panelContent: const Text('Chat content'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('YOLO'), findsOneWidget);

      await tester.tap(find.text('YOLO'));
      expect(toggled, isTrue);
    });

    testWidgets('reveals panel content when open', (tester) async {
      await tester.pumpWidget(
        shell(
          isOpen: true,
          onToggle: () {},
          panelContent: const Text('Chat content'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Chat content'), findsOneWidget);
    });

    testWidgets('shows close icon when open', (tester) async {
      await tester.pumpWidget(
        shell(
          isOpen: true,
          onToggle: () {},
          panelContent: const SizedBox.expand(),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.text('YOLO'), findsNothing);
    });
  });
}
