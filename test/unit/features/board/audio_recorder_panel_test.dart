// covers-write: board.audio_recorder

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

BoardPanelInstance _panel({Map<String, dynamic>? state}) => BoardPanelInstance(
  id: 'panel-audio-1',
  type: AudioRecorderPlugin.kTypeId,
  title: 'Audio Recorder',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 380, height: 460),
  state: state ?? const AudioRecorderPlugin().initialState,
);

Widget _wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SizedBox(width: 380, height: 460, child: child)));

/// Minimal cloud ASR fake that returns a fixed transcript without touching the
/// network or any MethodChannel.
class _FakeCloud implements CloudTranscriber {
  @override
  Future<String> transcribeFromFile({
    required String audioPath,
    required VoiceSettings voiceSettings,
  }) async => 'hello transcript';
}

/// Forces the transcription pipeline onto the cloud backend so the test never
/// reaches the local MLX engine.
class _FakeSettings implements VoiceSettingsProvider {
  @override
  Future<VoiceSettings> loadVoiceSettings() async =>
      const VoiceSettings(useCloudAsr: true);
}

void main() {
  group('AudioRecorderConfig', () {
    test('round-trips through JSON and reads from panel state', () {
      const config = AudioRecorderConfig(
        saveFolder: '/tmp/recordings',
        captureSystemAudio: false,
        captureMicrophone: true,
        format: 'wav',
      );

      final restored = AudioRecorderConfig.fromJson(config.toJson());
      expect(restored.saveFolder, '/tmp/recordings');
      expect(restored.captureSystemAudio, isFalse);
      expect(restored.captureMicrophone, isTrue);
      expect(restored.format, 'wav');

      final fromState = AudioRecorderConfig.fromState(<String, dynamic>{
        AudioRecorderConfig.configKey: config.toJson(),
      });
      expect(fromState.saveFolder, '/tmp/recordings');
      expect(fromState.captureSystemAudio, isFalse);
    });

    test('defaults are applied for missing keys', () {
      final config = AudioRecorderConfig.fromState(const <String, dynamic>{});
      expect(config.saveFolder, isEmpty);
      expect(config.captureSystemAudio, isTrue);
      expect(config.captureMicrophone, isTrue);
      expect(config.format, 'wav');
    });
  });

  group('AudioRecorderPanelContent', () {
    testWidgets('toggling a source writes the updated config to panel state',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(panel: _panel(), renderContext: renderContext),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('toggle-system-audio')));
      await tester.pump();

      expect(written, isNotNull);
      final config = AudioRecorderConfig.fromState(written!);
      expect(config.captureSystemAudio, isFalse);
      expect(config.captureMicrophone, isTrue);
    });

    testWidgets('record button is tappable without throwing in a test env',
        (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(panel: _panel(), renderContext: renderContext),
        ),
      );

      // The native capture engine is unavailable in the unit-test environment
      // (MethodChannel plugins are not registered), so the start attempt is
      // swallowed by the content's error handling and the UI stays stable.
      await tester.tap(find.text('Start recording'));
      await tester.pumpAndSettle();

      expect(find.text('Start recording'), findsOneWidget);
    });

    testWidgets('deleting a recording removes it from panel state',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      final panel = _panel(
        state: <String, dynamic>{
          ...const AudioRecorderPlugin().initialState,
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rec-1',
              'path': '/nonexistent/rec-test.wav',
              'name': 'rec-test.wav',
              'durationMs': 1234,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        },
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      await tester.tap(find.byKey(const ValueKey('delete-rec-test.wav')));
      await tester.pump();

      expect(written, isNotNull);
      final recordings = written!['recordings'] as List<dynamic>;
      expect(recordings, isEmpty);
    });

    testWidgets('each recording row offers a transcribe-to-markdown action',
        (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      final panel = _panel(
        state: <String, dynamic>{
          ...const AudioRecorderPlugin().initialState,
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rec-1',
              'path': '/nonexistent/rec-test.wav',
              'name': 'rec-test.wav',
              'durationMs': 1234,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        },
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      expect(
        find.byKey(const ValueKey('transcribe-rec-test.wav')),
        findsOneWidget,
      );
      expect(find.byTooltip('Transcribe to Markdown'), findsOneWidget);
    });

    testWidgets('transcribe writes markdown and opens a file preview panel',
        (tester) async {
      const audioPath = '/tmp/yoloit_tx/rec-test.wav';

      String? writtenMd;
      final savedWriter = AudioRecorderPanelContent.writeTranscriptFile;
      addTearDown(() {
        TranscriptionService.debugSetInstance(null);
        AudioRecorderPanelContent.writeTranscriptFile = savedWriter;
      });
      // In-memory writer: avoids real dart:io file writes, which leave the
      // headless widget-test isolate pending.
      AudioRecorderPanelContent.writeTranscriptFile = (path, contents) async {
        writtenMd = contents;
      };
      TranscriptionService.debugSetInstance(
        TranscriptionService.testInstance(
          cloud: _FakeCloud(),
          settings: _FakeSettings(),
        ),
      );

      String? capturedType;
      Map<String, dynamic>? capturedState;
      String? capturedTitle;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
        onCreateLinkedPanel: (typeId, state, title) async {
          capturedType = typeId;
          capturedState = state;
          capturedTitle = title;
          return 'panel-preview-1';
        },
      );

      final panel = _panel(
        state: <String, dynamic>{
          ...const AudioRecorderPlugin().initialState,
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rec-1',
              'path': audioPath,
              'name': 'rec-test.wav',
              'durationMs': 1234,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        },
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      final button = find.byKey(const ValueKey('transcribe-rec-test.wav'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      // No real IO is performed (the writer seam is in-memory), so a few
      // frames let the async transcribe continuation run to completion.
      for (var i = 0; i < 20 && capturedType == null; i++) {
        await tester.pump();
      }

      expect(capturedType, 'board.file.preview');
      expect(capturedState, isNotNull);
      expect(capturedState!['path'] as String, endsWith('rec-test.md'));
      expect(capturedState!['title'], 'rec-test.wav.md');
      expect(capturedTitle, 'rec-test.wav.md');
      expect(writtenMd, contains('hello transcript'));
    });
  });

  test('plugin exposes stable metadata and the write-covered type id', () {
    const plugin = AudioRecorderPlugin();
    expect(plugin.typeId, AudioRecorderPlugin.kTypeId);
    expect(plugin.typeId, 'board.audio_recorder');
    expect(plugin.displayName, 'Audio Recorder');
    expect(plugin.supportsHeadlessRender, isFalse);
    expect(plugin.initialState['isRecording'], isFalse);
    expect(plugin.initialState['recordings'], isA<List<dynamic>>());
    expect(
      AudioRecorderConfig.fromState(plugin.initialState).captureMicrophone,
      isTrue,
    );
  });
}
