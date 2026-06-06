import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_panel_models.dart';
import 'package:yoloit/features/board/chat/widgets/chat_running_tools_card.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

void main() {
  group('ChatRunningToolsCard', () {
    testWidgets('renders regular tool name', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatRunningToolsCard(
              tools: [
                const ChatToolCall(
                  toolCallId: 't1',
                  toolName: 'read_file',
                  arguments: {},
                ),
              ],
              subAgents: const {},
              subAgentPanels: const {},
              isSubAgentToolCall: (_) => false,
              onFocusPanel: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('read_file'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders sub-agent with Open button when panel mapped', (
      tester,
    ) async {
      String? focusedPanelId;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatRunningToolsCard(
              tools: [
                const ChatToolCall(
                  toolCallId: 'sa1',
                  toolName: 'sub_agent',
                  arguments: {'description': 'Research assistant'},
                ),
              ],
              subAgents: {
                'sa1': SubAgentRunState(
                  agentId: 'sa1',
                  agentName: 'Researcher',
                  agentDescription: 'Does research',
                ),
              },
              subAgentPanels: const {'sa1': 'panel-1'},
              isSubAgentToolCall: (n) => n == 'sub_agent',
              onFocusPanel: (id) => focusedPanelId = id,
            ),
          ),
        ),
      );

      expect(find.text('Researcher'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      await tester.tap(find.text('Open'));
      expect(focusedPanelId, 'panel-1');
    });

    testWidgets('renders fallback text when sub-agent state missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatRunningToolsCard(
              tools: [
                const ChatToolCall(
                  toolCallId: 'sa1',
                  toolName: 'sub_agent',
                  arguments: {},
                ),
              ],
              subAgents: const {},
              subAgentPanels: const {},
              isSubAgentToolCall: (_) => true,
              onFocusPanel: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Running sub-agent\u2026'), findsOneWidget);
    });

    testWidgets('shows event count for sub-agent with events', (tester) async {
      final state = SubAgentRunState(
        agentId: 'sa1',
        agentName: 'Coder',
        agentDescription: '',
      );
      state.events.add(
        SubAgentEvent(type: 'message', timestamp: DateTime.now()),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ChatRunningToolsCard(
              tools: [
                const ChatToolCall(
                  toolCallId: 'sa1',
                  toolName: 'sub_agent',
                  arguments: {},
                ),
              ],
              subAgents: {'sa1': state},
              subAgentPanels: const {},
              isSubAgentToolCall: (_) => true,
              onFocusPanel: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('1 events'), findsOneWidget);
    });
  });
}
