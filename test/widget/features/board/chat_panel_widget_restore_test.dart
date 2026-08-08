import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/chat/helpers/chat_sound_helper.dart';
import 'package:yoloit/features/board/chat/widgets/chat_message_list.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

import 'chat_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('chat panel session restore & reattach', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_restore_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      // Spawning `afplay` inside the fake-async zone leaks a pending timer.
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('re-attaches to a processing session and persists the new '
        'provider session id on done', (tester) async {
      final h = ChatPanelHarness(
        provider: 'opencode',
        panelId: 'chat-reattach-done',
        seedSession: (session) {
          session.restoreMessages([
            {'id': 'r1', 'role': 'assistant', 'content': 'earlier reply'},
          ]);
          session.restoreOpencodeSessionId('oc-seed');
          session.restoreCopilotSessionId('cop-seed');
          // A headless send started before the widget mounted — the session
          // is still streaming when initState runs.
          unawaited(session.sendMessage(text: 'started headless'));
        },
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      // _restoreSessionMessages picked up session messages + provider ids,
      // and _reattachSessionUICallbacks re-attached the UI (stop icon shows).
      expect(find.byType(ChatMessageList), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      // _restoreProviderSessionIds pushed the seeded ids back to the provider.
      expect(h.fake.getSessionId('test-session'), 'oc-seed');

      // The provider rotates the session id mid-turn.
      h.fake.setSessionId('test-session', 'oc-new');
      await h.finishTurn(tester);
      await tester.pump();

      // _handleReattachDone → _syncProviderSessionId persisted the new id.
      expect(h.updates.any((u) => u['opencodeSessionId'] == 'oc-new'), isTrue);
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('re-attach error path surfaces the stream error and persists '
        'it', (tester) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-reattach-error',
        seedSession: (session) {
          unawaited(session.sendMessage(text: 'will fail'));
        },
      );
      await h.pump(tester);
      addTearDown(h.dispose);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

      h.fake.emitError(StateError('boom'));
      await tester.pump();
      await tester.pump();

      // _handleReattachError synced the error message from the session and
      // persisted it; the send button recovered.
      final persisted =
          h.updates
              .where((u) => u['messages'] is List)
              .expand((u) => (u['messages'] as List).cast<Map<String, dynamic>>())
              .toList();
      expect(
        persisted.any((m) => (m['content'] as String).contains('Error')),
        isTrue,
      );
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
    });

    testWidgets('restores the seeded opencode session id into the provider', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'opencode',
        panelId: 'chat-restore-opencode',
        seedSession: (session) => session.restoreOpencodeSessionId('oc-seed'),
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      // _restoreProviderSessionIds copied the session id into the widget and
      // re-applied it to the provider + session.
      expect(h.fake.getSessionId('test-session'), 'oc-seed');
      expect(h.session.opencodeSessionId, 'oc-seed');
    });

    testWidgets('restores the seeded copilot session id into the provider', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-restore-copilot',
        seedSession: (session) => session.restoreCopilotSessionId('cop-seed'),
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      expect(h.fake.getSessionId('test-session'), 'cop-seed');
      expect(h.session.copilotSessionId, 'cop-seed');
    });

    testWidgets('first mount feeds persisted messages and usage into a fresh '
        'session', (tester) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-first-mount',
        extraState: {
          'messages': [
            ChatMessage(
              id: 'p1',
              role: ChatRole.user,
              content: 'persisted question',
              timestamp: DateTime.utc(2026, 7, 1),
            ).toJson(),
            ChatMessage(
              id: 'p2',
              role: ChatRole.assistant,
              content: 'persisted answer',
              timestamp: DateTime.utc(2026, 7, 1, 0, 1),
              tokenUsage: const ChatTokenUsage(outputTokens: 5),
            ).toJson(),
          ],
          'lastUsage': const ChatTokenUsage(outputTokens: 7).toJson(),
        },
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      // _restoreSessionMessages fed the persisted panel state into the fresh
      // session (messages + last usage).
      expect(h.session.messages, hasLength(2));
      expect(h.session.lastUsage?.outputTokens, 7);
      expect(find.byType(ChatMessageList), findsOneWidget);
    });
  });

  group('chat panel didUpdateWidget', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_didupdate_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('applies provider switches, follow-up drafts and CLI pending '
        'messages', (tester) async {
      final h = ChatPanelHarness(
        provider: 'opencode',
        panelId: 'chat-didupdate',
        extraState: const {'opencodeSessionId': 'oc-saved'},
      );
      await h.pump(tester);
      addTearDown(h.dispose);
      final baseState = Map<String, dynamic>.of(h.panelState);

      // 1) Switch provider opencode → copilot and queue a follow-up draft.
      const copilotConfig = ChatSessionConfig(
        sessionName: 'test-session',
        workingDir: '/tmp',
        provider: 'copilot',
      );
      final stateA = {
        ...baseState,
        'config': copilotConfig.toJson(),
        '_followUpDraft': 'queued draft',
      };
      await h.rebuild(tester, stateA);
      await tester.pump();

      // _onConfigChanged swapped the provider on the live session.
      expect(h.session.config.provider, 'copilot');
      // didUpdateWidget picked up the follow-up draft — banner is visible.
      expect(find.text('queued draft'), findsOneWidget);

      // 2) Switch back copilot → opencode: the saved session id is re-applied.
      const opencodeConfig = ChatSessionConfig(
        sessionName: 'test-session',
        workingDir: '/tmp',
        provider: 'opencode',
        model: 'fake-model',
      );
      final stateB = {...stateA, 'config': opencodeConfig.toJson()};
      h.fake.setSessionId('test-session', 'changed');
      await h.rebuild(tester, stateB);
      await tester.pump();

      expect(h.session.config.provider, 'opencode');
      expect(h.fake.getSessionId('test-session'), 'oc-saved');

      // 3) A new CLI pending message is consumed and sent with attachments.
      final stateC = {
        ...stateB,
        '_cliPendingMessage': 'cli follow-up',
        '_cliPendingAttachments': ['/tmp/a.png'],
      };
      await h.rebuild(tester, stateC);
      await tester.pump();

      expect(h.fake.sentMessages, ['cli follow-up']);
      expect(h.fake.sentAttachments.last, ['/tmp/a.png']);

      // 4) Rebuilding with the same pending message does not send it again.
      await h.rebuild(tester, {...stateC});
      await tester.pump();
      expect(h.fake.sentMessages, ['cli follow-up']);

      await h.finishTurn(tester);
      await tester.pump();
    });
  });

  group('chat panel slash navigation', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_slash_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    const manyModels = [
      ChatModelInfo(id: 'fake-model', displayName: 'Fake Model'),
      ChatModelInfo(id: 'gpt-5', displayName: 'GPT 5', providerGroup: 'OpenAI'),
      ChatModelInfo(id: 'm3', displayName: 'Model 3'),
      ChatModelInfo(id: 'm4', displayName: 'Model 4'),
      ChatModelInfo(id: 'm5', displayName: 'Model 5'),
      ChatModelInfo(id: 'm6', displayName: 'Model 6'),
      ChatModelInfo(id: 'm7', displayName: 'Model 7'),
      ChatModelInfo(id: 'm8', displayName: 'Model 8'),
      ChatModelInfo(id: 'm9', displayName: 'Model 9'),
      ChatModelInfo(id: 'm10', displayName: 'Model 10'),
      ChatModelInfo(id: 'm11', displayName: 'Model 11'),
      ChatModelInfo(id: 'm12', displayName: 'Model 12'),
    ];

    testWidgets('model slash filters by query and Enter selects the '
        'highlighted model', (tester) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-model-slash',
        models: manyModels,
      );
      await h.pump(tester);
      addTearDown(h.dispose);
      final field = find.byType(TextField);

      // Typing a query after /model filters the suggestion list.
      await tester.enterText(field, '/model gp');
      await tester.pump();
      expect(find.text('GPT 5'), findsOneWidget);
      expect(find.text('Model 3'), findsNothing);

      // Reset the query, then navigate deep into the list (scrolls the
      // highlight into view) and confirm with Enter.
      await tester.enterText(field, '/model');
      await tester.pump();
      for (var i = 0; i < 10; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      // _selectHighlightedModel picked the 11th model and persisted it.
      expect(
        h.updates.any((u) => (u['config'] as Map?)?['model'] == 'm11'),
        isTrue,
      );
      // Enter was consumed by the slash menu — nothing was sent.
      expect(h.fake.sentMessages, isEmpty);
    });

    testWidgets('plain slash Tab autocompletes /yolo and Enter consumes it', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-yolo-slash',
      );
      await h.pump(tester);
      addTearDown(h.dispose);
      final field = find.byType(TextField);

      // /y filters the chips to the yolo command; Tab autocompletes it.
      await tester.enterText(field, '/y');
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(tester.widget<TextField>(field).controller?.text, '/yolo ');

      // Escape hides the panel suggestions; Enter consumes the bare command
      // locally instead of sending it.
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(h.fake.sentMessages, isEmpty);
    });
  });
}
