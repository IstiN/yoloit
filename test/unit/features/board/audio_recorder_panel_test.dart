// covers-write: board.audio_recorder

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/board/audio_recorder/transcription_service.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';
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

/// Cloud ASR fake that always fails, to exercise the transcribe error path.
class _ThrowingCloud implements CloudTranscriber {
  @override
  Future<String> transcribeFromFile({
    required String audioPath,
    required VoiceSettings voiceSettings,
  }) async => throw StateError('cloud down');
}

/// Records `revealInFinder` calls instead of spawning a real `open` process.
class _RecordingLauncher extends PlatformLauncher {
  final List<String> revealed = <String>[];

  @override
  Future<void> openUrl(String url) async {}

  @override
  Future<void> revealInFinder(String path) async {
    revealed.add(path);
  }

  @override
  Future<void> openTerminal(String workdir) async {}
}

Map<String, dynamic> _rec(
  String name, {
  String? path,
  int durationMs = 1234,
  String id = 'rec-1',
}) => <String, dynamic>{
  'id': id,
  'path': path ?? '/nonexistent/$name',
  'name': name,
  'durationMs': durationMs,
  'sizeBytes': 0,
  'createdAt': 0,
  'format': 'wav',
};

Map<String, dynamic> _stateWith(Map<String, dynamic> patch) =>
    <String, dynamic>{...const AudioRecorderPlugin().initialState, ...patch};

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

    testWidgets('renders the last error from panel state', (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(state: _stateWith(<String, dynamic>{'lastError': 'boom'})),
            renderContext: renderContext,
          ),
        ),
      );

      expect(find.text('boom'), findsOneWidget);
    });

    testWidgets('recording state shows stop button, elapsed, disabled toggles',
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
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'isRecording': true,
                'elapsedMs': 65000,
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      expect(find.text('Stop recording'), findsOneWidget);
      expect(find.text('01:05'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('toggle-system-audio')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('toggle-microphone')));
      await tester.pump();
      expect(written, isNull);
    });

    testWidgets('elapsed label formats zero and clamps large values',
        (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      Widget content(int elapsedMs) => _wrap(
        AudioRecorderPanelContent(
          panel: _panel(
            state: _stateWith(<String, dynamic>{
              'isRecording': true,
              'elapsedMs': elapsedMs,
            }),
          ),
          renderContext: renderContext,
        ),
      );

      await tester.pumpWidget(content(0));
      expect(find.text('00:00'), findsOneWidget);

      // 400000 s is clamped to 359999 s => 5999 minutes, 59 seconds.
      await tester.pumpWidget(content(400000000));
      expect(find.text('5999:59'), findsOneWidget);
    });

    testWidgets('recording count label pluralizes', (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      Widget content(List<Map<String, dynamic>> recordings) => _wrap(
        AudioRecorderPanelContent(
          panel: _panel(
            state: _stateWith(<String, dynamic>{'recordings': recordings}),
          ),
          renderContext: renderContext,
        ),
      );

      await tester.pumpWidget(content(<Map<String, dynamic>>[]));
      expect(find.text('0 recordings'), findsOneWidget);

      await tester.pumpWidget(content(<Map<String, dynamic>>[_rec('a.wav')]));
      expect(find.text('1 recording'), findsOneWidget);

      await tester.pumpWidget(
        content(<Map<String, dynamic>>[
          _rec('a.wav'),
          _rec('b.wav', id: 'rec-2'),
        ]),
      );
      expect(find.text('2 recordings'), findsOneWidget);
    });

    testWidgets('recording row shows the name and formatted duration',
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
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('rec-test.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      expect(find.text('rec-test.wav'), findsOneWidget);
      expect(find.text('00:01'), findsOneWidget);
    });

    testWidgets('reveal delegates to PlatformLauncher.revealInFinder',
        (tester) async {
      final original = PlatformLauncher.instance;
      final fake = _RecordingLauncher();
      PlatformLauncher.setInstance(fake);
      addTearDown(() => PlatformLauncher.setInstance(original));

      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('rec-test.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('reveal-rec-test.wav')));
      await tester.pump();

      expect(fake.revealed, <String>['/nonexistent/rec-test.wav']);
    });

    testWidgets('playback failure surfaces an error instead of throwing',
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
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('rec-test.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // media_kit's native player is unavailable in the unit-test
      // environment, so the play attempt lands in the catch path.
      await tester.tap(find.byKey(const ValueKey('play-rec-test.wav')));
      for (var i = 0; i < 20 && written == null; i++) {
        await tester.pump();
      }

      expect(written, isNotNull);
      expect(written!['lastError'] as String, contains('Playback failed'));
    });

    testWidgets('transcribe failure surfaces an error via panel state',
        (tester) async {
      addTearDown(() => TranscriptionService.debugSetInstance(null));
      TranscriptionService.debugSetInstance(
        TranscriptionService.testInstance(
          cloud: _ThrowingCloud(),
          settings: _FakeSettings(),
        ),
      );

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
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('rec-test.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      final button = find.byKey(const ValueKey('transcribe-rec-test.wav'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        final error = written?['lastError'];
        if (error is String && error.contains('Transcription failed')) break;
      }

      expect(written, isNotNull);
      expect(written!['lastError'] as String, contains('Transcription failed'));
    });

    testWidgets('transcribe maps an uppercase .WAV path to .md',
        (tester) async {
      const audioPath = '/tmp/yoloit_tx/REC-2.WAV';

      final savedWriter = AudioRecorderPanelContent.writeTranscriptFile;
      addTearDown(() {
        TranscriptionService.debugSetInstance(null);
        AudioRecorderPanelContent.writeTranscriptFile = savedWriter;
      });
      AudioRecorderPanelContent.writeTranscriptFile = (path, contents) async {};
      TranscriptionService.debugSetInstance(
        TranscriptionService.testInstance(
          cloud: _FakeCloud(),
          settings: _FakeSettings(),
        ),
      );

      Map<String, dynamic>? capturedState;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
        onCreateLinkedPanel: (typeId, state, title) async {
          capturedState = state;
          return 'panel-preview-1';
        },
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[
                  _rec('REC-2.WAV', path: audioPath),
                ],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      final button = find.byKey(const ValueKey('transcribe-REC-2.WAV'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      for (var i = 0; i < 20 && capturedState == null; i++) {
        await tester.pump();
      }

      expect(capturedState, isNotNull);
      expect(capturedState!['path'] as String, endsWith('REC-2.md'));
      expect(capturedState!['title'], 'REC-2.WAV.md');
    });

    testWidgets('transcribe appends .md for non-wav recordings',
        (tester) async {
      const audioPath = '/tmp/yoloit_tx/voice.m4a';

      final savedWriter = AudioRecorderPanelContent.writeTranscriptFile;
      addTearDown(() {
        TranscriptionService.debugSetInstance(null);
        AudioRecorderPanelContent.writeTranscriptFile = savedWriter;
      });
      AudioRecorderPanelContent.writeTranscriptFile = (path, contents) async {};
      TranscriptionService.debugSetInstance(
        TranscriptionService.testInstance(
          cloud: _FakeCloud(),
          settings: _FakeSettings(),
        ),
      );

      Map<String, dynamic>? capturedState;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
        onCreateLinkedPanel: (typeId, state, title) async {
          capturedState = state;
          return 'panel-preview-1';
        },
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[
                  _rec('voice.m4a', path: audioPath),
                ],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      final button = find.byKey(const ValueKey('transcribe-voice.m4a'));
      await tester.ensureVisible(button);
      await tester.pump();
      await tester.tap(button);
      for (var i = 0; i < 20 && capturedState == null; i++) {
        await tester.pump();
      }

      expect(capturedState, isNotNull);
      expect(capturedState!['path'] as String, endsWith('voice.m4a.md'));
      expect(capturedState!['title'], 'voice.m4a.md');
    });

    testWidgets('folder row shows the board default or the configured folder',
        (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: _panel(), renderContext: renderContext)),
      );
      expect(find.text('Board default folder'), findsOneWidget);

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                AudioRecorderConfig.configKey:
                    const AudioRecorderConfig(saveFolder: '/tmp/recs').toJson(),
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );
      expect(find.text('/tmp/recs'), findsOneWidget);
    });

    testWidgets('_pickFolder writes the chosen directory into config',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      BoardFilePicker.debugPickDirectoryOverride =
          () async => '/tmp/test-recordings';
      addTearDown(() => BoardFilePicker.debugPickDirectoryOverride = null);

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: _panel(), renderContext: renderContext)),
      );

      await tester.tap(find.byKey(const ValueKey('choose-folder')));
      await tester.pump();

      expect(written, isNotNull);
      final config = AudioRecorderConfig.fromState(written!);
      expect(config.saveFolder, '/tmp/test-recordings');
    });

    testWidgets('_pickFolder does nothing when picker returns null',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      BoardFilePicker.debugPickDirectoryOverride = () async => null;
      addTearDown(() => BoardFilePicker.debugPickDirectoryOverride = null);

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: _panel(), renderContext: renderContext)),
      );

      await tester.tap(find.byKey(const ValueKey('choose-folder')));
      await tester.pump();

      expect(written, isNull);
    });

    testWidgets('_togglePlay early-returns when recording has no id',
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
        state: _stateWith(<String, dynamic>{
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': null,
              'path': '/nonexistent/rec.wav',
              'name': 'rec.wav',
              'durationMs': 100,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        }),
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      await tester.tap(find.byKey(const ValueKey('play-rec.wav')));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      // The early return means no error is ever written — the player is never
      // created so the catch path is never reached.
      expect(written, isNull);
    });

    testWidgets('_togglePlay early-returns when recording has no path',
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
        state: _stateWith(<String, dynamic>{
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rec-1',
              'path': null,
              'name': 'no-path.wav',
              'durationMs': 100,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        }),
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      await tester.tap(find.byKey(const ValueKey('play-no-path.wav')));
      for (var i = 0; i < 10; i++) {
        await tester.pump();
      }

      expect(written, isNull);
    });

    testWidgets('_ensurePlayer + _togglePlay catch path surfaces playback error',
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
        state: _stateWith(<String, dynamic>{
          'recordings': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': 'rec-1',
              'path': '/nonexistent/ensure-player-test.wav',
              'name': 'ensure-player-test.wav',
              'durationMs': 200,
              'sizeBytes': 0,
              'createdAt': 0,
              'format': 'wav',
            },
          ],
        }),
      );

      await tester.pumpWidget(
        _wrap(AudioRecorderPanelContent(panel: panel, renderContext: renderContext)),
      );

      // media_kit's native player is unavailable in the unit-test
      // environment, so _ensurePlayer creates a Player that throws during
      // open(), exercising the catch block in _togglePlay.
      await tester.tap(find.byKey(const ValueKey('play-ensure-player-test.wav')));
      for (var i = 0; i < 20 && written == null; i++) {
        await tester.pump();
      }

      expect(written, isNotNull);
      expect(written!['lastError'] as String, contains('Playback failed'));
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
