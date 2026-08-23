import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/chat/chat_panel_widget.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/chat/helpers/chat_sound_helper.dart';
import 'package:yoloit/features/board/chat/widgets/chat_changed_files_strip.dart';
import 'package:yoloit/features/board/chat/widgets/chat_message_list.dart';
import 'package:yoloit/features/board/chat/widgets/model_search_dialog.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

import 'chat_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('unconfigured chat panel shows setup even with saved messages', (
    tester,
  ) async {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    final panel = BoardPanelInstance(
      id: 'chat-panel',
      type: ChatPanelPlugin.kTypeId,
      title: 'AI Chat',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 500),
      state: {
        'configured': false,
        'config':
            const ChatSessionConfig(sessionName: '', workingDir: '').toJson(),
        'messages': [
          ChatMessage(
            id: 'msg-old',
            role: ChatRole.user,
            content: 'привет',
            timestamp: DateTime.utc(2026, 6, 2),
          ).toJson(),
        ],
      },
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: SizedBox(
              width: 520,
              height: 620,
              child: ChatPanelWidget(panel: panel, onUpdateState: (_) {}),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Provider'), findsOneWidget);
    expect(find.text('Start Chat'), findsOneWidget);
    expect(find.text('Message...'), findsNothing);
  });

  group('configured chat panel interactions', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_widget_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      // Spawning `afplay` inside the fake-async zone leaks a pending timer.
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('full send flow streams events and persists session id', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'opencode',
        autoSessionId: 'oc-1',
        panelId: 'chat-send-flow',
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'hello world');
      expect(h.fake.sentMessages, ['hello world']);
      expect(h.fake.sentRuntimeContexts.single?.panelId, 'chat-send-flow');
      expect(
        h.fake.sentRuntimeContexts.single?.availableBoardsSummary,
        contains('Board 1'),
      );

      // Ignored tool calls never reach the active tool map.
      h.fake.emit(chatToolStartEvent('tc0', 'report_intent'));
      await tester.pump();
      h.fake.emit(chatToolCompleteEvent('tc0', content: 'Intent logged'));
      await tester.pump();

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.assistantMessageStart,
          rawType: 'assistant.message_start',
          data: {'messageId': 'm1'},
        ),
      );
      await tester.pump();
      h.fake.emit(chatDeltaEvent('Hi '));
      h.fake.emit(chatDeltaEvent('there'));
      await tester.pump();
      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'messageId': 'm1', 'content': 'Hi there'},
        ),
      );
      await tester.pump();

      // A mutating tool call surfaces changed files.
      h.fake.emit(
        chatToolStartEvent('tc1', 'edit', arguments: {'path': '/tmp/a.dart'}),
      );
      await tester.pump();
      h.fake.emit(
        chatToolCompleteEvent('tc1', content: 'updated file /tmp/a.dart'),
      );
      await tester.pump();

      // The changed files strip surfaces the mutated file.
      expect(find.byType(ChatChangedFilesStrip), findsOneWidget);
      expect(find.textContaining('a.dart'), findsWidgets);

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.result,
          rawType: 'result',
          data: {
            'usage': {
              'outputTokens': 42,
              'premiumRequests': 1,
              'totalApiDurationMs': 100,
              'sessionDurationMs': 200,
              'codeChanges': {'linesAdded': 3, 'linesRemoved': 1},
            },
          },
        ),
      );
      await tester.pump();
      await h.finishTurn(tester);
      await tester.pump();

      // _captureProviderSessionIds persisted the opencode session id early.
      expect(
        h.updates.any((u) => u['opencodeSessionId'] == 'oc-1'),
        isTrue,
      );
      // _persistMessages stored the assistant + tool messages.
      final persisted =
          h.updates
              .where((u) => u['messages'] is List)
              .expand((u) => (u['messages'] as List).cast<Map<String, dynamic>>())
              .toList();
      expect(
        persisted.any((m) => m['content'] == 'Hi there'),
        isTrue,
      );
      expect(
        persisted.any((m) => m['role'] == 'tool'),
        isTrue,
      );
      // Turn completed: send button is back to the arrow (not stop).
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('queues follow-up while busy and auto-sends it on done', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        autoSessionId: 'cop-9',
        panelId: 'chat-follow-up',
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'first');
      expect(h.fake.sentMessages, ['first']);

      // While the agent is busy, Enter queues a follow-up instead of sending.
      await h.typeAndSend(tester, 'second');
      expect(h.fake.sentMessages, ['first']);
      expect(find.text('second'), findsOneWidget);

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'messageId': 'm2', 'content': 'reply'},
        ),
      );
      await tester.pump();
      await h.finishTurn(tester);
      await tester.pump();
      await tester.pump();

      // _handleSendDone persisted the copilot session id and auto-sent the
      // queued follow-up.
      expect(h.updates.any((u) => u['copilotSessionId'] == 'cop-9'), isTrue);
      expect(h.fake.sentMessages, ['first', 'second']);

      await h.finishTurn(tester);
      await tester.pump();

      // Slash commands are consumed locally and never reach the provider.
      await h.typeAndSend(tester, '/context');
      expect(h.fake.sentMessages, ['first', 'second']);

      // Shift+Enter must not send.
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump(const Duration(milliseconds: 350));
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(h.fake.sentMessages, ['first', 'second']);

      // Cmd+V triggers smart paste (clipboard empty in tests — must not throw
      // and must not send).
      await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(h.fake.sentMessages, ['first', 'second']);
    });

    testWidgets('syncs UI when the session changes externally (CLI send)', (
      tester,
    ) async {
      final h = ChatPanelHarness(provider: 'copilot', panelId: 'chat-cli-driven');
      await h.pump(tester);
      addTearDown(h.dispose);

      // Simulate a headless CLI send against the live session.
      final session = ChatSessionManager.instance.sessions['chat-cli-driven']!;
      await session.sendMessage(text: 'from cli');
      await tester.pump();

      // The widget attached itself as the UI: send button became a stop icon.
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'messageId': 'm3', 'content': 'cli reply'},
        ),
      );
      await tester.pump();
      await h.finishTurn(tester);
      await tester.pump();

      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      final persisted =
          h.updates
              .where((u) => u['messages'] is List)
              .expand((u) => (u['messages'] as List).cast<Map<String, dynamic>>())
              .toList();
      expect(persisted.any((m) => m['content'] == 'from cli'), isTrue);
      expect(persisted.any((m) => m['content'] == 'cli reply'), isTrue);
    });

    testWidgets('sub-agent events build a linked markdown log panel', (
      tester,
    ) async {
      final h = ChatPanelHarness(provider: 'copilot', panelId: 'chat-subagent');
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'run agents');

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.subagentStarted,
          rawType: 'subagent.started',
          data: {
            'agentId': 'a1',
            'agentDisplayName': 'Researcher',
            'agentDescription': 'Finds things',
          },
        ),
      );
      await tester.pump();
      await tester.pump();

      // _createAgentLogPanel used _buildAgentMarkdown for the initial content.
      expect(h.createdPanels, hasLength(1));
      expect(h.createdPanels.single.$1, 'board.note.markdown');
      expect(h.createdPanels.single.$3, '🤖 Researcher');
      final initialMd =
          h.createdPanels.single.$2['markdown'] as String? ?? '';
      expect(initialMd, contains('# 🤖 Researcher'));
      expect(initialMd, contains('> Finds things'));
      expect(initialMd, contains('*Running…*'));

      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.subagentToolStart,
          rawType: 'tool.execution_start',
          data: {'agentId': 'a1', 'toolName': 'grep'},
        ),
      );
      await tester.pump();
      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.subagentToolComplete,
          rawType: 'tool.execution_complete',
          data: {
            'agentId': 'a1',
            'toolName': 'grep',
            'success': false,
            'result': {'content': 'boom'},
          },
        ),
      );
      await tester.pump();
      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.subagentMessage,
          rawType: 'assistant.message',
          data: {'agentId': 'a1', 'content': 'working on it'},
        ),
      );
      await tester.pump();
      h.fake.emit(
        const ChatEvent(
          type: ChatEventType.subagentCompleted,
          rawType: 'subagent.completed',
          data: {'agentId': 'a1'},
        ),
      );
      await tester.pump();
      await h.finishTurn(tester);
      await tester.pump();

      // No crash, updates kept flowing; agent panel id was registered.
      expect(h.fake.sentMessages, ['run agents']);
    });

    testWidgets('/yolo mention injects panel summaries into the prompt', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-yolo',
        extraPanels: const [
          BoardPanelInstance(
            id: 'n1',
            type: 'board.note.markdown',
            title: 'Notes',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {'markdown': 'remember this'},
          ),
          BoardPanelInstance(
            id: 'k1',
            type: 'board.kanban',
            title: 'Tasks',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {
              'columns': ['Todo'],
              'cards': [
                {'title': 'Ship it', 'columnIndex': 0},
              ],
            },
          ),
        ],
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'check [panel:Notes|n1] and [panel:Tasks|k1]');

      final prompt = h.fake.sentMessages.single;
      // The session tokenizes the prompt, collapsing all whitespace runs to
      // single spaces before it reaches the provider.
      expect(prompt, startsWith('check and Referenced board panels:'));
      expect(prompt, contains('- Notes [board.note.markdown] (id: n1)'));
      expect(prompt, contains('Markdown preview: remember this'));
      expect(prompt, contains('- Tasks [board.kanban] (id: k1)'));
      expect(prompt, contains('- Ship it'));

      // Runtime context carried board + panels summaries.
      final ctx = h.fake.sentRuntimeContexts.single;
      expect(ctx?.availableBoardsSummary, contains('Board 1'));
      expect(ctx?.currentBoardPanelsSummary, contains('Notes'));

      await h.finishTurn(tester);
      await tester.pump();
    });

    testWidgets('consumes a CLI pending message on mount', (tester) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-cli-pending',
        extraState: const {'_cliPendingMessage': 'do the thing'},
      );
      await h.pump(tester);
      addTearDown(h.dispose);
      await tester.pump();

      expect(h.fake.sentMessages, ['do the thing']);
      // The pending marker was cleared from the panel state.
      expect(
        h.updates.any(
          (u) =>
              !u.containsKey('_cliPendingMessage') &&
              u.containsKey('configured'),
        ),
        isTrue,
      );

      await h.finishTurn(tester);
      await tester.pump();
    });

    testWidgets('cursor provider captures and persists its session id', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'cursor',
        autoSessionId: 'cur-1',
        panelId: 'chat-cursor',
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'hi cursor');
      h.fake.emit(chatDeltaEvent('yo'));
      // Delta events are coalesced by the session core (~60ms flush).
      // Wait past the streaming delta flush interval (100ms).
      await tester.pump(const Duration(milliseconds: 150));

      // _captureProviderSessionIds persisted the cursor session id early.
      expect(h.updates.any((u) => u['cursorSessionId'] == 'cur-1'), isTrue);

      await h.finishTurn(tester);
      await tester.pump();
      // _persistMessages kept it in the persisted config snapshot too.
      expect(
        h.updates.any(
          (u) => (u['config'] as Map?)?['cursorSessionId'] == 'cur-1',
        ),
        isTrue,
      );
    });

    testWidgets('restores messages and cursor session id from the session', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'cursor',
        panelId: 'chat-restore',
        seedSession: (session) {
          session.restoreMessages([
            {'id': 'r1', 'role': 'user', 'content': 'restored hello'},
          ]);
          session.restoreCursorSessionId('cur-saved');
        },
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      // _restoreSessionMessages picked up the seeded session messages.
      expect(find.byType(ChatMessageList), findsOneWidget);
      // _restoreProviderSessionIds pushed the cursor id back to the provider.
      expect(h.fake.getSessionId('test-session'), 'cur-saved');
    });

    testWidgets('slash menus navigate, autocomplete and dismiss via keyboard', (
      tester,
    ) async {
      final h = ChatPanelHarness(provider: 'copilot', panelId: 'chat-slash');
      await h.pump(tester);
      addTearDown(h.dispose);
      final field = find.byType(TextField);

      // /model menu: arrows move the highlight, Tab selects the model.
      await tester.enterText(field, '/model');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(
        h.updates.any((u) => (u['config'] as Map?)?['model'] == 'fake-model'),
        isTrue,
      );

      // Escape closes the menu; Enter then runs the /model command, opening
      // the model picker dialog instead of sending a message.
      await tester.enterText(field, '/model');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();
      expect(find.byType(ModelSearchDialog), findsOneWidget);
      await tester.tapAt(const Offset(2, 2));
      await tester.pump();
      expect(h.fake.sentMessages, isEmpty);

      // Plain slash Tab autocompletes the first command; /yolo is consumed
      // locally once its menu is dismissed with Escape.
      await tester.enterText(field, '/');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      await tester.enterText(field, '/yolo');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(h.fake.sentMessages, isEmpty);
    });
  });
}
