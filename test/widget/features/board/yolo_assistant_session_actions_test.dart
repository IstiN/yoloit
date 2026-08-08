import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

import 'yolo_assistant_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final env = YoloAssistantTestEnv();

  String panelStateMode() => env.panelState['mode'] as String? ?? 'text';

  setUp(env.setUp);
  tearDown(env.tearDown);

  group('session actions', () {
    testWidgets('new session resets chat and recreates provider on next send', (
      tester,
    ) async {
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'first message');
      expect(env.fakeProvider.sendCount, 1);
      expect(env.factoryCreations, 1);
      expect(env.messages(), isNotEmpty);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(env.messages(), isEmpty);
      expect(panelStateMode(), 'text');

      await env.typeAndSend(tester, 'second session message');
      expect(env.fakeProvider.sendCount, 2);
      // Provider was dropped with the session, so it was re-created.
      expect(env.factoryCreations, 2);
    });

    testWidgets('clear chat empties messages and drops the provider', (
      tester,
    ) async {
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'to be cleared');
      expect(env.messages(), isNotEmpty);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pump();
      expect(env.messages(), isEmpty);

      await env.typeAndSend(tester, 'after clear');
      expect(env.factoryCreations, 2);
    });

    testWidgets('history dialog lists and restores a persisted session', (
      tester,
    ) async {
      await env.pumpAssistant(tester);

      // Pre-seed a restorable session (metadata in prefs, messages in the
      // per-session JSON file) with real-async I/O.
      await tester.runAsync(() async {
        await ChatSessionHistory.instance.upsert(
          ChatSessionEntry(
            id: 'yolo-seed-1',
            sessionName: 'restore me please',
            provider: 'cloud:openrouter',
            model: 'gpt-x',
            workingDir: '',
            createdAt: DateTime(2026, 8, 1),
            messageCount: 2,
          ),
          messages: [
            {
              'id': 'u1',
              'role': 'user',
              'content': 'restore me please',
              'timestamp': '2026-08-01T10:00:00.000Z',
            },
            {
              'id': 'a1',
              'role': 'assistant',
              'content': 'restored answer',
              'timestamp': '2026-08-01T10:01:00.000Z',
            },
          ],
        );
      });

      await tester.tap(find.byIcon(Icons.history));
      await tester.runAsync(() async {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      expect(find.text('Yolo session history'), findsOneWidget);
      expect(find.textContaining('restore me please'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.byTooltip('Restore'));
        // The restore handler reads the session file with real dart:io.
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pumpAndSettle();
      final restored = env.messages();
      expect(
        restored.firstWhere((m) => m['role'] == 'user')['content'],
        'restore me please',
      );
    });

    testWidgets('add and remove skills updates the panel state', (
      tester,
    ) async {
      await env.pumpAssistant(tester);

      // The skills bar lives in voice mode.
      await tester.tap(find.byIcon(Icons.graphic_eq));
      await tester.pump();

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.text('Add Skill'), findsOneWidget);

      await tester.tap(find.text('Code Analysis'));
      await tester.pumpAndSettle();
      expect(
        (env.panelState['activeSkills'] as List<dynamic>),
        contains('Code Analysis'),
      );

      // Delete the 'Terminal' chip via its delete icon.
      final terminalChip = find.ancestor(
        of: find.text('Terminal'),
        matching: find.byType(InputChip),
      );
      await tester.tap(
        find.descendant(of: terminalChip, matching: find.byIcon(Icons.close)),
      );
      await tester.pump();
      expect(
        (env.panelState['activeSkills'] as List<dynamic>),
        isNot(contains('Terminal')),
      );
    });

    testWidgets('tools dialog disable destructive persists disabled names', (
      tester,
    ) async {
      await env.pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.settings_input_component_outlined));
      await tester.pumpAndSettle();
      expect(find.text('YoLo tools'), findsOneWidget);

      await tester.tap(find.text('Disable destructive'));
      await tester.pump();
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      final disabled =
          (env.panelState['disabledLocalToolNames'] as List<dynamic>)
              .cast<String>();
      expect(disabled, isNotEmpty);
      final sorted = List<String>.from(disabled)..sort();
      expect(disabled, sorted);
    });

    testWidgets('voice mode toggle shows placeholder and switches back', (
      tester,
    ) async {
      await env.pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.graphic_eq));
      await tester.pump();
      expect(panelStateMode(), 'voice');
      expect(find.text('Tap to speak'), findsOneWidget);

      await tester.tap(find.text('Tap to speak'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Voice-to-Voice coming soon'), findsOneWidget);
      // Dismiss the snackbar deterministically so it no longer covers the
      // bottom button (its dismiss timer/animation is marginal to pump out).
      tester
          .state<ScaffoldMessengerState>(
            find.byType(ScaffoldMessenger),
          )
          .hideCurrentSnackBar();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.text('Back to text'));
      await tester.pump();
      expect(panelStateMode(), 'text');
      expect(find.byType(TextField), findsOneWidget);
    });
  });

  group('clipboard and logs', () {
    testWidgets('copy chat log from the menu copies the transcript', (
      tester,
    ) async {
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'log this message');

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy chat log'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(env.clipboardText, contains('log this message'));
      expect(find.text('Full chat log copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('debug logs dialog simulate adds a session entry', (
      tester,
    ) async {
      await env.pumpAssistant(tester);

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LLM debug logs'));
      await tester.pumpAndSettle();
      expect(find.text('LLM Debug Logs'), findsOneWidget);

      await tester.tap(find.text('Simulate'));
      await tester.pump();
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();

      // Reopen: the simulated session is listed.
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('LLM debug logs'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('[Simulation]'),
        findsWidgets,
      );
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
    });

    testWidgets('long press on the user bubble copies its content', (
      tester,
    ) async {
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'copy me now');

      // Long-press the bubble padding: the SelectableText itself consumes
      // long-press gestures for text selection.
      final bubbleText = find.text('copy me now', findRichText: true);
      final textRect = tester.getRect(bubbleText);
      await tester.longPressAt(textRect.centerLeft.translate(-6, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(env.clipboardText, 'copy me now');
      expect(find.text('Copied to clipboard'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('send edge events', () {
    testWidgets('skips empty deltas and renders a failed tool completion', (
      tester,
    ) async {
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': ''},
        ),
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {},
        ),
        ChatEvent(
          type: ChatEventType.toolStart,
          rawType: 'tool.execution_start',
          data: {'toolName': 'yoloit_panels', 'toolCallId': 'call-9'},
        ),
        ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'tool.execution_complete',
          data: {
            'toolCallId': 'call-9',
            'toolName': 'yoloit_panels',
            'result': {'content': 'disk full'},
            'success': false,
          },
        ),
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'content': ''},
        ),
        ChatEvent(type: ChatEventType.result, rawType: 'result', data: {}),
      ];
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'edge cases');

      final tool =
          env.messages().firstWhere((m) => m['id'] == 'call-9');
      expect(tool['success'], isFalse);
      expect(tool['rawResult'], 'disk full');
      // Failed tool bubble shows the error styling.
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('finalize keeps the streamed delta text over the echo', (
      tester,
    ) async {
      // _finalizeAssistantReply re-renders the accumulated deltas, replacing
      // the content set by the assistant.message event.
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'draft'},
        ),
        ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'content': 'final text'},
        ),
      ];
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'replace check');

      expect(
        env.messages().firstWhere((m) => m['role'] == 'assistant')['content'],
        'draft',
      );
    });
  });

  group('voice ASR branches', () {
    testWidgets('cloud ASR without config shows a copyable ASR error dialog', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'voice_settings_v1': jsonEncode({
          'useCloudAsr': true,
          'convertWavToMp3': false,
          'useChatModelForCloudAsr': false,
          'cloudAsrConfigId': 'cfg-missing',
          'cloudAsrModel': 'whisper-1',
        }),
      });
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      await env.pumpAssistant(tester, controller: controller);

      await controller.startMic();
      env.recordPlatform.byteStreamCtrl!.add(
        Uint8List.fromList(List<int>.generate(320, (i) => i % 256)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // Push the error dialog from a real-async block (cross-zone recorder
      // stop, config resolution, transcription throw), then render and
      // close it with fake-zone frames. stopMic stays pending on the dialog
      // until it is closed below.
      await tester.runAsync(() async {
        unawaited(controller.stopMic());
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pumpAndSettle();

      expect(find.text('ASR error'), findsOneWidget);
      expect(env.fakeProvider.sendCount, 0);

      // Copy action puts the error text on the clipboard.
      await tester.tap(find.text('Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(env.clipboardText, contains('Cloud ASR'));
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('ASR error'), findsNothing);

      // stopMic now finalizes the failed run (real dart:io writes).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 500)),
      );

      // The failed run is still persisted for benchmarking.
      final samplesDir = Directory(
        '${env.tempHome.path}/Library/Application Support/yoloit/asr_samples',
      );
      final metaFile = samplesDir
          .listSync()
          .whereType<File>()
          .singleWhere((f) => f.path.endsWith('.json'));
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      expect(meta['asrMode'], 'cloud');
      expect(meta['asrStatus'], 'error');
      expect(meta['asrModel'], 'whisper-1');
      expect(meta['error'], isNotEmpty);
    });

    testWidgets('denied recorder permission shows the mic hint dialog', (
      tester,
    ) async {
      env.recordPlatform.hasPermissionResult = false;
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      await env.pumpAssistant(tester, controller: controller);

      // Do NOT await startMic here: the denied-permission path opens the
      // hint dialog and startMic only completes after it is closed below.
      unawaited(controller.startMic());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microphone access required'), findsOneWidget);

      await tester.tap(find.text('Copy reset command'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(env.clipboardText, contains('tccutil'));
      expect(find.text('Copied reset command'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Microphone access required'), findsNothing);
      expect(env.fakeProvider.sendCount, 0);
    });
  });
}
