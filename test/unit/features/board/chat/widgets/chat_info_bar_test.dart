import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/widgets/chat_info_bar.dart';

void main() {
  group('ChatInfoBar', () {
    Widget buildBar({
      String workingDir = '/tmp',
      String provider = 'copilot',
      String model = 'gpt-4',
      bool autopilot = false,
      String? reasoningEffort,
      int totalOutputTokens = 0,
      bool isProcessing = false,
      VoidCallback? onAutopilotToggle,
      VoidCallback? onCycleReasoningEffort,
      VoidCallback? onCopySession,
      VoidCallback? onShowHistory,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: ChatInfoBar(
            workingDir: workingDir,
            provider: provider,
            model: model,
            autopilot: autopilot,
            reasoningEffort: reasoningEffort,
            totalOutputTokens: totalOutputTokens,
            isProcessing: isProcessing,
            onAutopilotToggle: onAutopilotToggle ?? () {},
            onCycleReasoningEffort: onCycleReasoningEffort ?? () {},
            onCopySession: onCopySession ?? () {},
            onShowHistory: onShowHistory ?? () {},
            shortPath: (p) => p.split('/').last,
          ),
        ),
      );
    }

    testWidgets('renders working dir and model', (tester) async {
      await tester.pumpWidget(buildBar(workingDir: '/home/user/proj', model: 'claude'));

      expect(find.text('proj'), findsOneWidget);
      expect(find.text('claude'), findsOneWidget);
    });

    testWidgets('toggles autopilot on tap', (tester) async {
      var toggled = false;
      await tester.pumpWidget(
        buildBar(onAutopilotToggle: () => toggled = true),
      );

      await tester.tap(find.byIcon(Icons.rocket_launch));
      expect(toggled, isTrue);
    });

    testWidgets('cycles reasoning effort on tap', (tester) async {
      var cycled = false;
      await tester.pumpWidget(
        buildBar(onCycleReasoningEffort: () => cycled = true),
      );

      await tester.tap(find.text('Effort'));
      expect(cycled, isTrue);
    });

    testWidgets('displays reasoning effort label', (tester) async {
      await tester.pumpWidget(buildBar(reasoningEffort: 'high'));

      expect(find.text('Effort: high'), findsOneWidget);
    });

    testWidgets('shows token count when positive', (tester) async {
      await tester.pumpWidget(buildBar(totalOutputTokens: 42));

      expect(find.text('∑42'), findsOneWidget);
    });

    testWidgets('shows progress indicator when processing', (tester) async {
      await tester.pumpWidget(buildBar(isProcessing: true));

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('triggers copy session callback', (tester) async {
      var copied = false;
      await tester.pumpWidget(buildBar(onCopySession: () => copied = true));

      await tester.tap(find.byTooltip('Copy session'));
      expect(copied, isTrue);
    });

    testWidgets('triggers history callback', (tester) async {
      var shown = false;
      await tester.pumpWidget(buildBar(onShowHistory: () => shown = true));

      await tester.tap(find.byIcon(Icons.history));
      expect(shown, isTrue);
    });
  });
}
