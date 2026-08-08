import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/assistant/yolo_assistant_widget.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

import 'yolo_assistant_test_env.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final env = YoloAssistantTestEnv();

  setUp(env.setUp);
  tearDown(env.tearDown);

  group('send pipeline', () {
    testWidgets('streams assistant, tool and result events into chat state', (
      tester,
    ) async {
      env.fakeProvider.events = [
        const ChatEvent(
          type: ChatEventType.sessionStatus,
          rawType: 'session.skills_loaded',
        ),
        const ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'Hello '},
        ),
        const ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'world'},
        ),
        const ChatEvent(
          type: ChatEventType.toolStart,
          rawType: 'tool.execution_start',
          data: {
            'toolName': 'yoloit_panels',
            'toolCallId': 'call-1',
            'arguments': {'board': 'board-1'},
          },
        ),
        const ChatEvent(
          type: ChatEventType.toolComplete,
          rawType: 'tool.execution_complete',
          data: {
            'toolCallId': 'call-1',
            'toolName': 'yoloit_panels',
            'result': {'content': 'panel list'},
            'success': true,
          },
        ),
        const ChatEvent(
          type: ChatEventType.assistantMessage,
          rawType: 'assistant.message',
          data: {'content': 'Hello world final'},
        ),
        const ChatEvent(
          type: ChatEventType.result,
          rawType: 'result',
          data: {
            'usage': {'totalTokens': 42},
          },
        ),
      ];
      env.fakeProvider.beforeEvents = () async {
        final executor = env.capturedExecutors.single;
        // Successful panel:create retargets the assistant note target.
        executor.onToolCompleted!(
          'panel:create',
          {'type': 'board.note.markdown', 'board': 'board-1'},
          jsonEncode({
            'ok': true,
            'command': 'panel:create',
            'stdout': jsonEncode({
              'panel': {'id': 'note-9', 'title': 'Shopping'},
            }),
          }),
          true,
        );
        // Failed note tool keeps the previous target.
        executor.onToolCompleted!(
          'note:write',
          {'panel': 'note-2'},
          jsonEncode({'ok': false, 'error': 'disk full'}),
          false,
        );
      };
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'hello board');

      expect(env.fakeProvider.sendCount, 1);
      expect(env.fakeProvider.lastMessage, 'hello board');
      // Default prefs: assistant provider falls back to cloud:openrouter.
      expect(env.capturedProviderTypes, ['cloud:openrouter']);

      final msgs = env.messages();
      expect(msgs.firstWhere((m) => m['role'] == 'user')['content'],
          'hello board');
      expect(
        msgs.firstWhere((m) => m['role'] == 'assistant')['content'],
        'Hello world',
      );
      final tool = msgs.firstWhere((m) => m['role'] == 'tool');
      expect(tool['id'], 'call-1');
      expect(tool['rawResult'], 'panel list');
      expect(tool['success'], isTrue);
      expect(tool['content'], 'Done: yoloit_panels');
      // Tool completion patched the assistant target note.
      expect(env.panelState['lastTargetNotePanelId'], 'note-9');
      expect(env.panelState['lastTargetNotePanelTitle'], 'Shopping');
    });

    testWidgets('empty input does not start a send', (tester) async {
      await env.pumpAssistant(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward));
      await env.settleSend(tester);

      expect(env.fakeProvider.sendCount, 0);
      expect(env.messages(), isEmpty);
    });

    testWidgets('second send is ignored while generating; stop cancels', (
      tester,
    ) async {
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'partial'},
        ),
      ];
      env.fakeProvider.gate = Completer<void>();
      await env.pumpAssistant(tester, controller: controller);

      await tester.enterText(find.byType(TextField), 'long task');
      unawaited(controller.sendDraft());
      // Let the pipeline reach the provider (secure-read zero-timeout needs
      // a couple of pumps to fire).
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      // Second send hits the _isGeneratingReply guard.
      await controller.sendDraft();
      expect(env.fakeProvider.sendCount, 1);

      await tester.tap(find.byIcon(Icons.stop_rounded));
      await env.settleSend(tester);

      expect(env.fakeProvider.stopCalled, isTrue);
      expect(env.fakeProvider.sendCount, 1);
      expect(
        env.messages().firstWhere((m) => m['role'] == 'assistant')['content'],
        'partial',
      );
      // Mirrored overlay settled on the final output state.
      expect(env.panelState['assistantStatus'], 'output');
      expect(env.panelState['voicePrompt'], 'long task');
      expect(env.panelState['voiceOverlayHidden'], isFalse);
    });

    testWidgets('provider error is rendered as an assistant error message', (
      tester,
    ) async {
      env.fakeProvider.errorToThrow = StateError('kaboom');
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'boom please');

      expect(
        env.messages().firstWhere((m) => m['role'] == 'assistant')['content'],
        contains('Error: Bad state: kaboom'),
      );
    });

    testWidgets('saved local preference is normalized to cloud', (
      tester,
    ) async {
      // Local models are hidden (see `chore: hide local model functionality`):
      // the settings service rewrites a saved 'local' preference to 'cloud'.
      SharedPreferences.setMockInitialValues({
        'assistant_provider_type_v1': 'local',
      });
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'local run');

      expect(env.capturedProviderTypes, ['cloud:openrouter']);
    });

    testWidgets('cloud preference uses the active config id', (tester) async {
      SharedPreferences.setMockInitialValues({
        'assistant_provider_type_v1': 'cloud',
        'cloud_llm_active_config_v1': 'cfg-1',
      });
      await env.seedCloudConfigs([env.cloudConfigJson('cfg-1')]);
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'cloud run');

      expect(env.capturedProviderTypes, ['cloud:cfg-1']);
    });

    testWidgets('cloud preference without active config uses the first saved', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'assistant_provider_type_v1': 'cloud',
      });
      await env.seedCloudConfigs([env.cloudConfigJson('cfg-7')]);
      await env.pumpAssistant(tester);
      await env.typeAndSend(tester, 'cloud fallback');

      expect(env.capturedProviderTypes, ['cloud:cfg-7']);
    });

    testWidgets('enter key sends, shift+enter and other keys do not', (
      tester,
    ) async {
      await env.pumpAssistant(tester);
      await tester.enterText(find.byType(TextField), 'via enter');

      // Non-enter key is ignored by the key handler.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      // Shift+enter inserts a newline instead of sending.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await env.settleSend(tester);
      expect(env.fakeProvider.sendCount, 0);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await env.settleSend(tester);
      expect(env.fakeProvider.sendCount, 1);
      expect(env.fakeProvider.lastMessage, contains('via enter'));
    });

    testWidgets('target panel feeds the runtime context; provider is reused', (
      tester,
    ) async {
      env.panelState['targetPanelId'] = 'note-1';
      await env.pumpAssistant(
        tester,
        extraPanels: [env.notePanel('note-1', 'Notes')],
      );

      await env.typeAndSend(tester, 'first');
      await env.typeAndSend(tester, 'second');

      expect(env.fakeProvider.sendCount, 2);
      // Same provider type → provider instance reused, factory called once.
      expect(env.factoryCreations, 1);
    });
  });

  group('voice pipeline', () {
    testWidgets('records mic, saves ASR sample and sends direct audio', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'cfg-1',
      });
      await env.seedCloudConfigs([env.cloudConfigJson('cfg-1')]);
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'Voice answer'},
        ),
      ];
      await env.pumpAssistant(tester, controller: controller);

      // The whole mic flow runs in the fake zone up to the stop: the
      // recorder platform is faked and the amplitude timer advances with
      // pumps. stopMic runs in a real-async block because finalizing the
      // run writes the ASR sample files with real dart:io I/O.
      await controller.startMic();
      env.recordPlatform.byteStreamCtrl!.add(
        Uint8List.fromList(List<int>.generate(320, (i) => i % 256)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(
        () => controller.stopMic(sendAfterTranscription: true),
      );
      await env.settleVoice(tester);

      // ASR sample persisted for benchmarking (sync reads: the writes
      // completed inside the real-async stopMic call).
      final samplesDir = Directory(
        '${env.tempHome.path}/Library/Application Support/yoloit/asr_samples',
      );
      expect(samplesDir.existsSync(), isTrue);
      final files = samplesDir.listSync().whereType<File>().toList();
      final wav = files.singleWhere((f) => f.path.endsWith('.wav'));
      final metaFile = files.singleWhere((f) => f.path.endsWith('.json'));
      expect(wav.lengthSync(), greaterThan(44));
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      expect(meta['asrMode'], 'direct_audio');
      expect(meta['asrStatus'], 'ok');
      expect(meta['transcriptChars'], -1);
      expect(meta['asrModel'], 'gpt-x');
      expect(meta['asrProvider'], 'openrouter');

      // Audio was attached directly and the reply streamed back.
      expect(env.fakeProvider.sendCount, 1);
      expect(env.fakeProvider.lastAudioContent, isNotNull);
      expect(
        env.fakeProvider.lastAudioContent!.single['type'],
        'input_audio',
      );
      expect(env.messages().first['content'], '🎤 Voice message');
      expect(env.panelState['voicePrompt'], '🎤 Voice message');
      expect(env.panelState['assistantStatus'], 'output');
      expect(env.panelState['voiceResponse'], 'Voice answer');
    });

    testWidgets('direct audio converts WAV to MP3 when enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'cloud_llm_active_config_v1': 'cfg-1',
        'voice_settings_v1':
            '{"useCloudAsr":true,"convertWavToMp3":true,'
            '"useChatModelForCloudAsr":true}',
      });
      await env.seedCloudConfigs([env.cloudConfigJson('cfg-1')]);
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      env.fakeProvider.events = const [
        ChatEvent(
          type: ChatEventType.assistantDelta,
          rawType: 'assistant.message_delta',
          data: {'deltaContent': 'Voice answer'},
        ),
      ];
      await env.pumpAssistant(tester, controller: controller);

      await controller.startMic();
      // One second of 16 kHz mono PCM so ffmpeg has enough frames to encode.
      env.recordPlatform.byteStreamCtrl!.add(
        Uint8List.fromList(List<int>.generate(32000, (i) => i % 256)),
      );
      await tester.pump(const Duration(milliseconds: 100));
      // stopMic runs real-async: the WAV→MP3 conversion spawns a real
      // ffmpeg process (or falls back to WAV when ffmpeg is absent).
      await tester.runAsync(
        () => controller.stopMic(sendAfterTranscription: true),
      );
      await env.settleVoice(tester);

      expect(env.fakeProvider.sendCount, 1);
      final audio = env.fakeProvider.lastAudioContent;
      expect(audio, isNotNull);
      expect(audio!.single['type'], 'input_audio');
      final payload = audio.single['input_audio'] as Map<String, Object?>;
      final ffmpegAvailable =
          Process.runSync('sh', const ['-lc', 'command -v ffmpeg'])
              .exitCode ==
          0;
      expect(payload['format'], ffmpegAvailable ? 'mp3' : 'wav');
      final data = base64Decode(payload['data'] as String);
      expect(data.length, greaterThan(0));

      // The ASR sample metadata still records the direct-audio run.
      final samplesDir = Directory(
        '${env.tempHome.path}/Library/Application Support/yoloit/asr_samples',
      );
      final metaFile = samplesDir
          .listSync()
          .whereType<File>()
          .singleWhere((f) => f.path.endsWith('.json'));
      final meta =
          jsonDecode(metaFile.readAsStringSync()) as Map<String, dynamic>;
      expect(meta['asrMode'], 'direct_audio');
      expect(meta['asrStatus'], 'ok');
    });

    testWidgets('stop without recorded audio skips transcription and send', (
      tester,
    ) async {      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      await env.pumpAssistant(tester, controller: controller);

      await controller.startMic();
      await tester.pump(const Duration(milliseconds: 100));
      unawaited(controller.stopMic(sendAfterTranscription: true));
      await env.settleVoice(tester);

      expect(env.fakeProvider.sendCount, 0);
      expect(
        Directory(
          '${env.tempHome.path}/Library/Application Support/yoloit/asr_samples',
        ).existsSync(),
        isFalse,
      );
    });

    testWidgets('cancel recording resets the overlay and drops audio', (
      tester,
    ) async {
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      await env.pumpAssistant(tester, controller: controller);

      await controller.startMic();
      env.recordPlatform.byteStreamCtrl!.add(Uint8List.fromList([1, 2, 3]));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.runAsync(() => controller.cancelMic());
      await tester.pump();

      expect(env.fakeProvider.sendCount, 0);
      expect(env.panelState['assistantStatus'], 'idle');
      expect(env.panelState['voiceOverlayHidden'], isTrue);
    });

    testWidgets('mic stream failure surfaces a copyable error dialog', (
      tester,
    ) async {
      env.recordPlatform.startStreamException =
          Exception('mic hardware missing');
      final controller = YoloAssistantController();
      addTearDown(controller.dispose);
      await env.pumpAssistant(tester, controller: controller);

      // Do NOT await startMic here: the failure path opens an error dialog
      // and startMic only completes after it is closed below.
      unawaited(controller.startMic());
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Microphone error'), findsOneWidget);
      expect(find.textContaining('mic hardware missing'), findsOneWidget);

      // Copy action puts the error text on the clipboard.
      await tester.tap(find.text('Copy'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(env.clipboardText, contains('mic hardware missing'));
      await tester.pump(const Duration(seconds: 3));

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Microphone error'), findsNothing);
      expect(env.fakeProvider.sendCount, 0);
    });
  });

  group('request preview dialog', () {
    testWidgets('builds request markdown and persists model settings', (
      tester,
    ) async {
      env.panelState['messages'] = [
        {
          'id': 'u1',
          'role': 'user',
          'content': 'first question',
          'timestamp': '2026-08-01T10:00:00.000Z',
        },
        {
          'id': 't1',
          'role': 'tool',
          'toolName': 'panels',
          'content': 'yoloit panels board-1',
          'rawResult': '{"ok": true}',
          'arguments': {'board': 'board-1'},
          'success': true,
          'timestamp': '2026-08-01T10:01:00.000Z',
        },
        {
          'id': 'a1',
          'role': 'assistant',
          'content': 'first answer',
          'timestamp': '2026-08-01T10:02:00.000Z',
        },
      ];
      env.panelState['targetPanelId'] = 'note-1';
      await env.pumpAssistant(
        tester,
        extraPanels: [env.notePanel('note-1', 'Notes')],
      );

      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Preview next LLM request'));
        // Complete the popup pop animation so onSelected fires inside the
        // real-async zone, then let the prompt build (asset load plus the
        // fast, read-only `yoloit help --format short`) finish with real I/O.
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();

      expect(find.text('Chat session request'), findsOneWidget);
      expect(
        find.textContaining('Next YoLo Chat request preview',
            findRichText: true),
        findsOneWidget,
      );
      // System prompt includes the focus panel summary for note-1.
      expect(
        find.textContaining('### Focus panel', findRichText: true),
        findsOneWidget,
      );
      expect(
        find.textContaining('note-1', findRichText: true),
        findsWidgets,
      );

      // Editing the model settings persists them into the panel state.
      await tester.enterText(find.byType(TextFormField).at(0), '2048');
      await tester.pump();
      expect(env.panelState['localModelMaxOutputTokens'], 2048);

      await tester.enterText(find.byType(TextFormField).at(1), '1.5');
      await tester.pump();
      expect(env.panelState['localModelTemperature'], 1.5);

      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      expect(env.panelState['localModelEnableThinking'], isTrue);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Chat session request'), findsNothing);
    });
  });
}
