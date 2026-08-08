import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/platform/system_audio_bridge.dart';
import 'package:yoloit/features/board/audio_recorder/audio_recording_manager.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';

import '../../../widget/features/board/yolo_assistant_test_env.dart';

/// Polls [condition] with real-async pauses until it holds or [timeout]
/// elapses.
///
/// The full suite runs many isolates in parallel, so a fixed
/// `Future.delayed` after a tap is routinely outrun by real channel
/// round-trips and file I/O on a busy machine; every post-tap assertion in
/// this file waits on the actual outcome instead of a wall-clock guess.
Future<void> _waitFor(
  bool Function() condition, {
  required String reason,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final sw = Stopwatch()..start();
  while (!condition()) {
    if (sw.elapsed > timeout) {
      throw TimeoutException('timed out waiting for $reason');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

/// Scriptable system-audio bridge: never touches the native channels.
class _FakeSystemAudioBridge implements SystemAudioBridge {
  bool supported = true;
  bool grant = true;
  int requestCount = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<String> status() async => 'authorized';

  @override
  Future<bool> request() async {
    requestCount++;
    return grant;
  }

  @override
  Future<bool> openSettings() async => false;

  @override
  Future<void> startCapture({
    required int sampleRate,
    required int channels,
  }) async {}

  @override
  Future<void> stopCapture() async {}

  @override
  Stream<Uint8List> pcmStream() => const Stream<Uint8List>.empty();
}

void main() {
  const micChannel = MethodChannel('yoloit/microphone_permission');

  late Directory tempHome;
  late Directory recordingsDir;
  late _FakeSystemAudioBridge bridge;
  late SystemAudioBridge originalBridge;
  late FakeRecordPlatform recordPlatform;
  late RecordPlatform originalRecordPlatform;
  late List<Map<String, dynamic>> writes;

  // The manager is a process-wide singleton keyed by panel id, so tests that
  // touch it use distinct ids: a recording started by one test can then never
  // be mistaken for (or silently replace) another test's panel when async
  // work outlives its test under full-suite load.
  BoardPanelInstance panel({
    String id = 'panel-audio-1',
    Map<String, dynamic>? state,
  }) =>
      BoardPanelInstance(
        id: id,
        type: AudioRecorderPlugin.kTypeId,
        title: 'Audio Recorder',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 380, height: 460),
        state: state ?? const AudioRecorderPlugin().initialState,
      );

  Widget wrap(Widget child, {BoardCubit? cubit}) {
    final body = SizedBox(width: 380, height: 460, child: child);
    return MaterialApp(
      home: Scaffold(
        body: cubit == null
            ? body
            : BlocProvider.value(value: cubit, child: body),
      ),
    );
  }

  BoardPanelRenderContext renderContext() => BoardPanelRenderContext(
    isSelected: false,
    onFocus: () {},
    onDelete: () {},
    onUpdateState: writes.add,
    onShowEditor: () {},
  );

  void mockMicPermission({required bool granted}) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(micChannel, (call) async {
          if (call.method == 'request') return granted;
          return null;
        });
  }

  BoardCubit cubitWithPanel(Map<String, dynamic> panelState, {String? panelId}) {
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(
        boards: [
          BoardDocument(
            id: 'board-1',
            name: 'Test',
            panels: [panel(id: panelId ?? 'panel-audio-1', state: panelState)],
          ),
        ],
        activeBoardId: 'board-1',
        isLoaded: true,
      ),
    );
    return cubit;
  }

  Map<String, dynamic> stateWithConfig({
    bool captureSystemAudio = true,
    bool captureMicrophone = true,
    String saveFolder = '',
  }) => <String, dynamic>{
    ...const AudioRecorderPlugin().initialState,
    AudioRecorderConfig.configKey:
        AudioRecorderConfig(
          saveFolder: saveFolder,
          captureSystemAudio: captureSystemAudio,
          captureMicrophone: captureMicrophone,
        ).toJson(),
  };

  List<String> errors() => writes
      .map((w) => w['lastError'])
      .whereType<String>()
      .toList(growable: false);

  setUp(() {
    // BoardCubit persists board state through SharedPreferences.
    SharedPreferences.setMockInitialValues(<String, Object>{});
    writes = <Map<String, dynamic>>[];
    tempHome = Directory.systemTemp.createTempSync('audio_toggle_home_');
    recordingsDir = Directory.systemTemp.createTempSync('audio_toggle_recs_');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempHome.path));
    bridge = _FakeSystemAudioBridge();
    originalBridge = SystemAudioBridge.instance;
    SystemAudioBridge.instance = bridge;
    originalRecordPlatform = RecordPlatform.instance;
    recordPlatform = FakeRecordPlatform();
    RecordPlatform.instance = recordPlatform;
    mockMicPermission(granted: true);
  });

  tearDown(() async {
    await AudioRecordingManager.instance.disposeAll();
    SystemAudioBridge.instance = originalBridge;
    RecordPlatform.instance = originalRecordPlatform;
    PlatformDirs.setInstance(const MacosPlatformDirs());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(micChannel, null);
    if (tempHome.existsSync()) tempHome.deleteSync(recursive: true);
    if (recordingsDir.existsSync()) {
      recordingsDir.deleteSync(recursive: true);
    }
  });

  testWidgets('denies recording when microphone permission is not granted', (
    tester,
  ) async {
    mockMicPermission(granted: false);
    await tester.pumpWidget(
      wrap(AudioRecorderPanelContent(panel: panel(), renderContext: renderContext())),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      await _waitFor(
        () => errors().contains(
          'Microphone permission is required to record.',
        ),
        reason: 'mic permission error',
      );
    });
    await tester.pump();

    expect(errors(), contains('Microphone permission is required to record.'));
    expect(AudioRecordingManager.instance.isRecording('panel-audio-1'), isFalse);
    // The system-audio bridge is never asked when the mic check fails.
    expect(bridge.requestCount, 0);
  });

  testWidgets('reports when the board cannot be determined', (tester) async {
    await tester.pumpWidget(
      wrap(AudioRecorderPanelContent(panel: panel(), renderContext: renderContext())),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      await _waitFor(
        () => errors().contains(
          'Could not determine the board for this panel.',
        ),
        reason: 'board lookup error',
      );
    });
    await tester.pump();

    // No BoardCubit ancestor → the board lookup fails after the permission
    // and system-audio checks pass.
    expect(bridge.requestCount, 1);
    expect(errors(), contains('Could not determine the board for this panel.'));
  });

  testWidgets('system audio denial records mic-only and surfaces a hint', (
    tester,
  ) async {
    bridge.grant = false;
    await tester.pumpWidget(
      wrap(AudioRecorderPanelContent(panel: panel(), renderContext: renderContext())),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      // The flow continues after the hint and fails the board lookup (no
      // cubit here), so wait until the final error has landed.
      await _waitFor(
        () =>
            errors().isNotEmpty &&
            errors().last == 'Could not determine the board for this panel.',
        reason: 'board lookup error after system-audio hint',
      );
    });
    await tester.pump();

    expect(
      errors(),
      contains('Screen Recording permission denied; recording microphone only.'),
    );
    // The flow then continues and fails the board lookup (no cubit here).
    expect(errors().last, 'Could not determine the board for this panel.');
  });

  testWidgets('skips the system-audio bridge when capture is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      wrap(
        AudioRecorderPanelContent(
          panel: panel(state: stateWithConfig(captureSystemAudio: false)),
          renderContext: renderContext(),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      await _waitFor(
        () => errors().contains(
          'Could not determine the board for this panel.',
        ),
        reason: 'board lookup error',
      );
    });
    await tester.pump();

    expect(bridge.requestCount, 0);
    expect(errors(), contains('Could not determine the board for this panel.'));
  });

  testWidgets('starts a recording through the manager and stops it', (
    tester,
  ) async {
    const panelId = 'panel-audio-start-stop';
    final cubit = cubitWithPanel(
      stateWithConfig(
        captureSystemAudio: false,
        saveFolder: recordingsDir.path,
      ),
      panelId: panelId,
    );
    AudioRecordingManager.instance.setCubit(cubit);

    await tester.pumpWidget(
      wrap(
        AudioRecorderPanelContent(
          panel: panel(
            id: panelId,
            state: stateWithConfig(
              captureSystemAudio: false,
              saveFolder: recordingsDir.path,
            ),
          ),
          renderContext: renderContext(),
        ),
        cubit: cubit,
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      await _waitFor(
        () => AudioRecordingManager.instance.isRecording(panelId),
        reason: 'recording to start',
      );
    });
    await tester.pump();

    final manager = AudioRecordingManager.instance;
    expect(manager.isRecording(panelId), isTrue);
    expect(errors(), isNot(contains(startsWith('Recording failed'))));

    await tester.runAsync(() => manager.stop(panelId));
    expect(manager.isRecording(panelId), isFalse);
    final wavs = recordingsDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.wav'))
        .toList();
    expect(wavs, hasLength(1));
    expect(wavs.single.lengthSync(), greaterThanOrEqualTo(44));
  });

  testWidgets('tapping stop delegates to the manager', (tester) async {
    const panelId = 'panel-audio-stop-noop';
    await tester.pumpWidget(
      wrap(
        AudioRecorderPanelContent(
          panel: panel(
            id: panelId,
            state: <String, dynamic>{
              ...const AudioRecorderPlugin().initialState,
              'isRecording': true,
            },
          ),
          renderContext: renderContext(),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Stop recording'));
      // Stop with no active engine entry is a no-op, so there is no outcome
      // to poll; give the (empty) async stop path a moment to surface any
      // unexpected error before the negative assertions below.
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // No active engine entry: stop is a no-op and no error is surfaced.
    expect(AudioRecordingManager.instance.isRecording(panelId), isFalse);
    expect(errors(), isNot(contains(startsWith('Recording failed'))));
    expect(bridge.requestCount, 0);
  });

  testWidgets('a start failure surfaces a recording error', (tester) async {
    const panelId = 'panel-audio-start-failure';
    recordPlatform.startStreamException = Exception('no mic hardware');
    final cubit = cubitWithPanel(
      stateWithConfig(
        captureSystemAudio: false,
        saveFolder: recordingsDir.path,
      ),
      panelId: panelId,
    );
    AudioRecordingManager.instance.setCubit(cubit);

    await tester.pumpWidget(
      wrap(
        AudioRecorderPanelContent(
          panel: panel(
            id: panelId,
            state: stateWithConfig(
              captureSystemAudio: false,
              saveFolder: recordingsDir.path,
            ),
          ),
          renderContext: renderContext(),
        ),
        cubit: cubit,
      ),
    );

    await tester.runAsync(() async {
      await tester.tap(find.text('Start recording'));
      await _waitFor(
        () => errors().any((e) => e.startsWith('Recording failed:')),
        reason: 'recording error to surface',
      );
    });
    await tester.pump();

    expect(errors().last, startsWith('Recording failed:'));
    expect(AudioRecordingManager.instance.isRecording(panelId), isFalse);
  });
}
