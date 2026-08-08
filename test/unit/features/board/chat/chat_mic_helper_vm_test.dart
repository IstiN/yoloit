import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/chat/helpers/chat_mic_helper_vm.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_cubit.dart';
import 'package:yoloit/features/workspaces/bloc/workspace_state.dart';

const _micChannel = MethodChannel('yoloit/microphone_permission');

/// In-memory [RecordPlatform] so the record plugin never touches native
/// platform channels from tests.
class _FakeRecordPlatform implements RecordPlatform {
  bool permission = true;
  String? stopPath;
  Exception? startError;
  final startedPaths = <String>[];
  var disposed = false;

  @override
  Future<void> create(String recorderId) async {}

  @override
  Future<void> start(
    String recorderId,
    RecordConfig config, {
    required String path,
  }) async {
    final error = startError;
    if (error != null) throw error;
    startedPaths.add(path);
  }

  @override
  Future<Stream<Uint8List>> startStream(
    String recorderId,
    RecordConfig config,
  ) => throw UnimplementedError();

  @override
  Future<String?> stop(String recorderId) async => stopPath;

  @override
  Future<void> pause(String recorderId) async {}

  @override
  Future<void> resume(String recorderId) async {}

  @override
  Future<bool> isRecording(String recorderId) async => false;

  @override
  Future<bool> isPaused(String recorderId) async => false;

  @override
  Future<bool> hasPermission(String recorderId, {bool request = true}) async =>
      permission;

  @override
  Future<void> dispose(String recorderId) async {
    disposed = true;
  }

  @override
  Future<Amplitude> getAmplitude(String recorderId) async =>
      Amplitude(current: 0, max: 0);

  @override
  Future<bool> isEncoderSupported(
    String recorderId,
    AudioEncoder encoder,
  ) async =>
      true;

  @override
  Future<List<InputDevice>> listInputDevices(String recorderId) async =>
      const [];

  @override
  Future<void> cancel(String recorderId) async {}

  @override
  RecordIos? getIos(String recorderId) => null;

  @override
  Stream<RecordState> onStateChanged(String recorderId) =>
      const Stream<RecordState>.empty();

  @override
  void setOnConfigChanged(
    String recorderId,
    void Function(RecordConfig config)? handler,
  ) {}
}

class _MockWorkspaceCubit extends Mock implements WorkspaceCubit {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRecordPlatform recorder;
  late Directory tempDir;
  var nativeGranted = true;
  final originalRecordPlatform = RecordPlatform.instance;

  const config = ChatSessionConfig(sessionName: '', workingDir: '');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('chat_mic_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tempDir.path));
    recorder = _FakeRecordPlatform();
    RecordPlatform.instance = recorder;
    nativeGranted = true;
    CloudLlmSettingsService.secureReadTimeout = Duration.zero;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_micChannel, (call) async {
          if (call.method == 'request') return nativeGranted;
          return null;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_micChannel, null);
      RecordPlatform.instance = originalRecordPlatform;
      CloudLlmSettingsService.secureReadTimeout = const Duration(seconds: 8);
      // Restore the global default ASR state (cloud mode, no config id).
      await AgentConfigService.instance.saveDefaultAsr(mode: 'cloud');
      PlatformDirs.reset();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  Future<void> configureCloudAsr({String? configId}) =>
      AgentConfigService.instance.saveDefaultAsr(
        mode: 'cloud',
        configId: configId,
      );

  /// Pumps a minimal app with the cubits [SettingsPage.show] needs and
  /// returns a context below the ScaffoldMessenger.
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    final wsCubit = _MockWorkspaceCubit();
    when(() => wsCubit.state).thenReturn(const WorkspaceInitial());
    when(
      () => wsCubit.stream,
    ).thenAnswer((_) => const Stream<WorkspaceState>.empty());

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider<WorkspaceCubit>.value(
          value: wsCubit,
          child: Scaffold(
            body: Builder(
              builder: (context) {
                captured = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    return captured;
  }

  group('isAvailable', () {
    test('reports the desktop recorder as available', () {
      expect(ChatMicHandlerImpl().isAvailable, isTrue);
    });
  });

  /// Runs [ChatMicHandlerImpl.start] in the real-async zone. The handler must
  /// be constructed there too: `AudioRecorder`'s constructor launches a
  /// future in whatever zone is current, and awaiting it from another zone
  /// deadlocks the test.
  Future<void> startInRealZone(
    WidgetTester tester,
    BuildContext context, {
    required void Function({required bool recording, required bool transcribing})
    updateState,
    required Future<void> Function(String title, String message) showError,
  }) => tester.runAsync(() async {
    final handler = ChatMicHandlerImpl();
    await handler.start(
      context,
      config: config,
      updateState: updateState,
      showError: showError,
    );
  });

  group('start', () {
    testWidgets('opens settings and bails when cloud ASR is not configured', (
      tester,
    ) async {
      await tester.runAsync(configureCloudAsr); // mode cloud, but no config id
      final context = await pumpContext(tester);
      final stateUpdates = <bool>[];

      late Future<void> future;
      await tester.runAsync(() async {
        final handler = ChatMicHandlerImpl();
        future = handler.start(
          context,
          config: config,
          updateState: ({required recording, required transcribing}) =>
              stateUpdates.add(recording),
          showError: (title, message) async {},
        );
      });
      await tester.pump();
      await tester.pump();

      expect(
        find.text('Configure a cloud ASR provider in Settings → AI Models.'),
        findsOneWidget,
      );
      expect(find.byType(Dialog), findsOneWidget);

      // Dismiss the settings dialog so start() can complete.
      Navigator.of(context, rootNavigator: true).pop();
      await tester.pump();
      await tester.runAsync(() => future);
      expect(stateUpdates, isEmpty);
      expect(recorder.startedPaths, isEmpty);
    });

    testWidgets('shows an error when native mic permission is denied', (
      tester,
    ) async {
      await tester.runAsync(() => configureCloudAsr(configId: 'cfg-1'));
      nativeGranted = false;
      final context = await pumpContext(tester);
      final errors = <List<String>>[];

      await startInRealZone(
        tester,
        context,
        updateState: ({required recording, required transcribing}) {},
        showError: (title, message) async => errors.add([title, message]),
      );

      expect(errors.single.first, 'Microphone access required');
      expect(recorder.startedPaths, isEmpty);
    });

    testWidgets('shows an error when recorder permission is denied', (
      tester,
    ) async {
      await tester.runAsync(() => configureCloudAsr(configId: 'cfg-1'));
      recorder.permission = false;
      final context = await pumpContext(tester);
      final errors = <List<String>>[];

      await startInRealZone(
        tester,
        context,
        updateState: ({required recording, required transcribing}) {},
        showError: (title, message) async => errors.add([title, message]),
      );

      expect(errors.single.first, 'Microphone access required');
      expect(recorder.startedPaths, isEmpty);
    });

    testWidgets('starts recording when configuration and permissions pass', (
      tester,
    ) async {
      await tester.runAsync(() => configureCloudAsr(configId: 'cfg-1'));
      final context = await pumpContext(tester);
      final stateUpdates = <({bool recording, bool transcribing})>[];

      await startInRealZone(
        tester,
        context,
        updateState: ({required recording, required transcribing}) =>
            stateUpdates.add((
              recording: recording,
              transcribing: transcribing,
            )),
        showError: (title, message) async => fail('unexpected error: $title'),
      );

      expect(stateUpdates.single.recording, isTrue);
      expect(stateUpdates.single.transcribing, isFalse);
      expect(recorder.startedPaths.single, contains('yoloit_asr_'));
      expect(recorder.startedPaths.single, endsWith('.wav'));
    });

    testWidgets('recorder failure with permission reports a mic error', (
      tester,
    ) async {
      await tester.runAsync(() => configureCloudAsr(configId: 'cfg-1'));
      recorder.startError = Exception('boom');
      final context = await pumpContext(tester);
      final errors = <List<String>>[];

      await startInRealZone(
        tester,
        context,
        updateState: ({required recording, required transcribing}) {},
        showError: (title, message) async => errors.add([title, message]),
      );

      expect(errors.single.first, 'Microphone error');
      expect(errors.single[1], contains('boom'));
    });

    testWidgets('recorder failure without permission asks for access', (
      tester,
    ) async {
      await tester.runAsync(() => configureCloudAsr(configId: 'cfg-1'));
      recorder.startError = Exception('boom');
      recorder.permission = false;
      final context = await pumpContext(tester);
      final errors = <List<String>>[];

      await startInRealZone(
        tester,
        context,
        updateState: ({required recording, required transcribing}) {},
        showError: (title, message) async => errors.add([title, message]),
      );

      expect(errors.single.first, 'Microphone access required');
    });
  });

  group('stop', () {
    test('finishes without a transcript when no recording path exists', () async {
      final handler = ChatMicHandlerImpl();
      var finished = 0;

      await handler.stop(
        config: config,
        onTranscript: (_) => fail('no transcript expected'),
        onFinished: () => finished++,
      );

      expect(finished, 1);
    });

    test('cleans up the temp file when cloud ASR is not configured', () async {
      await configureCloudAsr(); // no config id → transcription returns ''
      final recording = File('${tempDir.path}/take.wav')
        ..writeAsStringSync('wav-bytes');
      recorder.stopPath = recording.path;
      final handler = ChatMicHandlerImpl();
      final transcripts = <String>[];
      var finished = 0;

      await handler.stop(
        config: config,
        onTranscript: transcripts.add,
        onFinished: () => finished++,
      );

      expect(transcripts, isEmpty);
      expect(finished, 1);
      expect(recording.existsSync(), isFalse);
    });

    test('survives a transcription failure and still cleans up', () async {
      // Configured, but no matching cloud config is stored → StateError.
      await configureCloudAsr(configId: 'missing-config');
      final recording = File('${tempDir.path}/take.wav')
        ..writeAsStringSync('wav-bytes');
      recorder.stopPath = recording.path;
      final handler = ChatMicHandlerImpl();
      var finished = 0;

      await handler.stop(
        config: config,
        onTranscript: (_) => fail('no transcript expected'),
        onFinished: () => finished++,
      );

      expect(finished, 1);
      expect(recording.existsSync(), isFalse);
    });
  });

  group('dispose', () {
    test('disposes the underlying recorder', () async {
      final handler = ChatMicHandlerImpl();
      await handler.dispose();
      expect(recorder.disposed, isTrue);
    });
  });
}
