import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/agent_card.dart';
import 'package:yoloit/features/mindmap/nodes/presentation/card_props.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildHarness(void Function(String data) onInput) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            height: 280,
            child: AgentCard(
              props: const AgentCardProps(
                name: 'Copilot',
                status: 'live',
                isRunning: true,
                typeName: 'Copilot',
                lastLines: ['hello'],
                repos: [RepoBranchInfo(repo: 'yoloit', branch: 'main')],
              ),
              onTerminalInput: onInput,
            ),
          ),
        ),
      ),
    );
  }

  group('AgentCard terminal input', () {
    testWidgets('sends typed characters after focus', (tester) async {
      final sent = <String>[];

      await tester.pumpWidget(buildHarness(sent.add));
      await tester.tap(find.byType(AgentCard));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA, character: 'a');
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);

      expect(sent, ['a']);
    });

    testWidgets('maps terminal control keys to PTY sequences', (tester) async {
      final sent = <String>[];

      await tester.pumpWidget(buildHarness(sent.add));
      await tester.tap(find.byType(AgentCard));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

      expect(sent, ['\x1b\r', '\x1b[A', '\x03']);
    });
  });

  group('AgentCard hook phase animation', () {
    Widget buildPhased(AgentCardProps props) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              height: 280,
              child: AgentCard(props: props),
            ),
          ),
        ),
      );
    }

    AgentCardProps propsFor(AgentPhase? phase) => AgentCardProps(
      name: 'Copilot',
      status: 'live',
      isRunning: true,
      lastLines: const ['hello'],
      hookPhase: phase,
    );

    testWidgets('shows the phase bar while active and hides it when cleared', (
      tester,
    ) async {
      await tester.pumpWidget(buildPhased(propsFor(const ThinkingPhase())));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('● Thinking…'), findsOneWidget);

      // Clearing the phase stops the glow animation and removes the bar.
      await tester.pumpWidget(buildPhased(propsFor(null)));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('● Thinking…'), findsNothing);
    });

    testWidgets('switches phases and updates the phase bar label', (
      tester,
    ) async {
      await tester.pumpWidget(buildPhased(propsFor(const ThinkingPhase())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('● Thinking…'), findsOneWidget);

      await tester.pumpWidget(
        buildPhased(propsFor(const ToolPhase('read_file'))),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('⚙ read_file'), findsOneWidget);

      await tester.pumpWidget(
        buildPhased(propsFor(const AwaitingApprovalPhase())),
      );
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('⚠ Waiting for approval'), findsOneWidget);

      await tester.pumpWidget(buildPhased(propsFor(const DonePhase())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('✓ Done'), findsOneWidget);

      await tester.pumpWidget(buildPhased(propsFor(const ErrorPhase())));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('✕ Error'), findsOneWidget);
    });

    testWidgets('idle session offers to start the terminal', (tester) async {
      var started = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 280,
                child: AgentCard(
                  props: const AgentCardProps(
                    name: 'Copilot',
                    status: 'idle',
                    isRunning: false,
                    isIdle: true,
                  ),
                  onSessionStart: () => started++,
                ),
              ),
            ),
          ),
        ),
      );

      expect(find.text('Saved session'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pump();
      expect(started, 1);
    });
  });
}
