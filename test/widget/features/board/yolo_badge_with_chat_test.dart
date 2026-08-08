import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/ui/yolo_badge_with_chat_vm.dart';

import 'yolo_assistant_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final env = YoloAssistantTestEnv();

  setUp(env.setUp);
  tearDown(env.tearDown);

  Future<YoloBadgeWithChatState> pumpBadge(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1400, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    const board = BoardDocument(
      id: 'board-1',
      name: 'Test board',
      viewport: BoardViewport(scale: 1),
    );
    env.cubit.emit(
      const BoardState(
        boards: [board],
        activeBoardId: 'board-1',
        isLoaded: true,
      ),
    );
    final key = GlobalKey<YoloBadgeWithChatState>();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: env.cubit,
            child: SizedBox(
              width: 420,
              height: 560,
              child: YoloBadgeWithChat(key: key),
            ),
          ),
        ),
      ),
    );
    // Past the 300 ms entrance timer.
    await tester.pump(const Duration(milliseconds: 500));
    return key.currentState!;
  }

  /// The badge rebuilds the embedded assistant with its in-memory panel, so
  /// the panel state doubles as a window into the badge's overlay state.
  String? badgeStatus(WidgetTester tester) {
    final assistant = tester.widget<YoloAssistantWidget>(
      find.byType(YoloAssistantWidget),
    );
    return assistant.panel.state['assistantStatus'] as String?;
  }

  void setOverlayStatus(
    YoloBadgeWithChatState state,
    String status, {
    String draft = '',
    String response = '',
    bool hidden = false,
  }) {
    state.debugSetBadgePanelState({
      'assistantStatus': status,
      'voiceDraft': draft,
      'voicePrompt': '',
      'voiceResponse': response,
      'voiceOverlayHidden': hidden,
    });
  }

  group('handleVoiceOverlayPrimaryAction', () {
    testWidgets('default (idle) status activates the overlay and starts the mic', (
      tester,
    ) async {
      final state = await pumpBadge(tester);
      expect(badgeStatus(tester), isNull);

      final action = state.handleVoiceOverlayPrimaryAction();
      await tester.pump(const Duration(milliseconds: 50));
      await action;
      await tester.pump();

      // The mic pipeline (faked) reported recording → overlay is listening.
      expect(badgeStatus(tester), 'listening');
    });

    testWidgets('in-flight statuses are ignored', (tester) async {
      final state = await pumpBadge(tester);

      for (final status in ['processing', 'thinking', 'responding']) {
        setOverlayStatus(state, status);
        await tester.pump();
        await state.handleVoiceOverlayPrimaryAction();
        await tester.pump();
        // No state change, no send, no mic start.
        expect(badgeStatus(tester), status);
      }
      expect(env.fakeProvider.sendCount, 0);
      expect(env.recordPlatform.byteStreamCtrl, isNull);
      // Flush overlay transition timers.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('output status re-activates the overlay', (tester) async {
      final state = await pumpBadge(tester);
      setOverlayStatus(state, 'output', response: 'Previous answer');
      await tester.pump();

      final action = state.handleVoiceOverlayPrimaryAction();
      await tester.pump(const Duration(milliseconds: 50));
      await action;
      await tester.pump();

      expect(badgeStatus(tester), 'listening');
      // Flush overlay transition timers.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('ready status with an empty draft activates the overlay', (
      tester,
    ) async {
      final state = await pumpBadge(tester);
      setOverlayStatus(state, 'ready', draft: '   ');
      await tester.pump();

      final action = state.handleVoiceOverlayPrimaryAction();
      await tester.pump(const Duration(milliseconds: 50));
      await action;
      await tester.pump();

      expect(env.fakeProvider.sendCount, 0);
      expect(badgeStatus(tester), 'listening');
    });

    testWidgets('ready status with a draft sends it through the assistant', (
      tester,
    ) async {
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'Badge answer'},
        ),
      ];
      final state = await pumpBadge(tester);

      // Open the chat drawer and type the draft into the assistant input.
      state.toggleChat();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.enterText(find.byType(TextField).first, 'badge draft');
      await tester.pump();

      setOverlayStatus(state, 'ready', draft: 'badge draft');
      await tester.pump();

      final action = state.handleVoiceOverlayPrimaryAction();
      await env.settleSend(tester);
      await action;

      expect(env.fakeProvider.sendCount, 1);
      // Voice-mirrored sends carry the ASR context prefix.
      expect(env.fakeProvider.lastMessage, contains('badge draft'));
      // The streamed reply was mirrored back onto the overlay.
      expect(badgeStatus(tester), 'output');
    });

    testWidgets('listening status stops the mic without audio to send', (
      tester,
    ) async {
      final state = await pumpBadge(tester);

      // Start listening first (default branch).
      final activate = state.handleVoiceOverlayPrimaryAction();
      await tester.pump(const Duration(milliseconds: 50));
      await activate;
      await tester.pump();
      expect(badgeStatus(tester), 'listening');

      // Primary action while listening stops the mic and asks to send; with
      // no recorded audio the run finalizes back to idle without sending.
      await tester.runAsync(() => state.handleVoiceOverlayPrimaryAction());
      await env.settleVoice(tester);

      expect(env.fakeProvider.sendCount, 0);
      expect(badgeStatus(tester), 'idle');
    });
  });
}
