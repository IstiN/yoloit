import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/chat/helpers/chat_sound_helper.dart';
import 'package:yoloit/features/board/chat/helpers/chat_subagent_note_helper.dart';
import 'package:yoloit/features/board/chat/widgets/chat_info_bar.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

import 'chat_panel_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('chat panel stop streaming', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_stop_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('stop button halts the stream and resets the composer', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-stop-stream',
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'hello agent');
      h.fake.emit(chatDeltaEvent('partial answer'));
      await tester.pump();
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
      expect(h.session.isProcessing, isTrue);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await tester.pump();
      await tester.pump();

      // _stopStreaming cleared streaming state, stopped the provider process
      // and re-synced the finalized messages from the session.
      expect(find.byIcon(Icons.arrow_upward), findsOneWidget);
      expect(h.session.isProcessing, isFalse);
      expect(h.fake.isRunning('test-session'), isFalse);
      expect(
        h.session.messages.any(
          (m) => m.role == ChatRole.user && m.content == 'hello agent',
        ),
        isTrue,
      );
      // Send button works again after stopping.
      await h.typeAndSend(tester, 'second try');
      expect(h.fake.sentMessages, ['hello agent', 'second try']);
      await h.finishTurn(tester);
    });
  });

  group('chat panel focus panel context', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_focus_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('sending with targetPanelId attaches a focus panel summary', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-focus-panel',
        extraPanels: const [
          BoardPanelInstance(
            id: 'note-1',
            type: 'board.note.markdown',
            title: 'Spec',
            bounds: BoardPanelBounds(x: 500, y: 0, width: 300, height: 200),
            state: {'markdown': '# Spec'},
          ),
        ],
        extraState: const {'targetPanelId': 'note-1'},
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'summarize the note');

      // _focusPanelSummary resolved the target panel from the current board
      // and injected its markdown summary into the runtime context.
      final ctx = h.fake.sentRuntimeContexts.single;
      expect(ctx, isNotNull);
      expect(ctx!.targetPanelSummary, contains('### Focus panel'));
      expect(ctx.targetPanelSummary, contains('- id: `note-1`'));
      expect(ctx.targetPanelSummary, contains('- title: Spec'));

      await h.finishTurn(tester);
    });

    testWidgets('unknown targetPanelId sends without a focus summary', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-focus-missing',
        extraState: const {'targetPanelId': 'no-such-panel'},
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'plain message');

      final ctx = h.fake.sentRuntimeContexts.single;
      expect(ctx, isNotNull);
      expect(ctx!.targetPanelSummary, isNull);

      await h.finishTurn(tester);
    });
  });

  group('chat panel session transcript', () {
    late Directory tempDir;
    String? clipboardText;

    void mockClipboard(WidgetTester tester) {
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          clipboardText =
              (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
    }

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_copy_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
      clipboardText = null;
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    /// The info bar's copy button (tool cards show a similar icon).
    Finder copySessionButton() => find.descendant(
      of: find.byType(ChatInfoBar),
      matching: find.byIcon(Icons.copy_all_outlined),
    );

    testWidgets('copy button writes the session transcript to the clipboard', (
      tester,
    ) async {
      mockClipboard(tester);
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-copy-session',
        seedSession:
            (session) => session.restoreMessages([
              {
                'id': 'm1',
                'role': 'user',
                'content': 'question one',
                'timestamp': '2026-07-01T00:00:00.000Z',
              },
              {
                'id': 'm2',
                'role': 'tool',
                'content': 'tool output',
                'toolName': 'read',
                'toolCallId': 'tc1',
              },
            ]),
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await tester.tap(copySessionButton());
      await tester.pump();
      // Let the confirmation snackbar run out so no timer leaks.
      await tester.pump(const Duration(seconds: 3));

      // _buildSessionTranscript rendered the header and both messages.
      final text = clipboardText;
      expect(text, isNotNull);
      expect(text, contains('Session: test-session'));
      expect(text, contains('Provider: copilot'));
      expect(text, contains('Messages: 2'));
      expect(text, contains('[2026-07-01T00:00:00.000Z] USER'));
      expect(text, contains('question one'));
      expect(text, contains('TOOL (read)'));
      expect(text, contains('tool output'));
    });

    testWidgets('transcript includes in-flight streaming content', (
      tester,
    ) async {
      mockClipboard(tester);
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-copy-streaming',
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await h.typeAndSend(tester, 'hi');
      h.fake.emit(chatDeltaEvent('half-written'));
      await tester.pump();

      await tester.tap(copySessionButton());
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));

      final text = clipboardText;
      expect(text, isNotNull);
      expect(text, contains('[streaming] ASSISTANT'));
      expect(text, contains('half-written'));

      await h.finishTurn(tester);
    });
  });

  group('chat panel link tap', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_link_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
    });

    tearDown(() {
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('tapping an https link opens a linked webpage panel', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-link-tap',
        seedSession:
            (session) => session.restoreMessages([
              {
                'id': 'm1',
                'role': 'assistant',
                'content': 'See [Flutter docs](https://flutter.dev/docs) now',
              },
            ]),
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      // _handleLinkTap routes web links to a linked board.webpage panel.
      await tester.tapOnText(find.textRange.ofSubstring('Flutter docs'));
      await tester.pump();

      expect(h.createdPanels, hasLength(1));
      final (typeId, state, title) = h.createdPanels.single;
      expect(typeId, 'board.webpage');
      expect(state['url'], 'https://flutter.dev/docs');
      expect(title, 'flutter.dev');
    });
  });

  group('chat panel send tool result to panel', () {
    late Directory tempDir;
    final createdNotes = <Map<String, Object?>>[];

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('chat_panel_note_test');
      PlatformDirs.setInstance(ChatTestPlatformDirs(tempDir.path));
      playChatCompletionSound = () async {};
      createdNotes.clear();
      createAgentNotePanel = ({
        required BuildContext context,
        required String boardName,
        required String title,
        required String content,
        String? workingDir,
      }) async {
        createdNotes.add({
          'boardName': boardName,
          'title': title,
          'content': content,
          'workingDir': workingDir,
        });
      };
    });

    tearDown(() {
      createAgentNotePanel = ChatSubagentNoteHelper.create;
      playChatCompletionSound = ChatSoundHelper.play;
      PlatformDirs.reset();
      tempDir.deleteSync(recursive: true);
    });

    testWidgets('send-to-panel on a tool result builds an agent note', (
      tester,
    ) async {
      final h = ChatPanelHarness(
        provider: 'copilot',
        panelId: 'chat-send-to-panel',
        seedSession:
            (session) => session.restoreMessages([
              {
                'id': 't1',
                'role': 'tool',
                'content': 'agent did the work',
                'toolName': 'task',
                'toolCallId': 'tc-9',
              },
            ]),
      );
      await h.pump(tester);
      addTearDown(h.dispose);

      await tester.tap(find.byIcon(Icons.note_add_outlined));
      await tester.pump();

      // _sendToolResultToPanel found the current board, composed the note
      // title + markdown body and called the note helper with the chat cwd.
      expect(createdNotes, hasLength(1));
      final note = createdNotes.single;
      expect(note['boardName'], 'Board 1');
      expect(note['title'], '🤖 task');
      expect(note['workingDir'], '/tmp');
      expect(note['content'] as String, contains('# 🤖 task'));
      expect(note['content'] as String, contains('agent did the work'));
    });
  });
}
