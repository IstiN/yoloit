import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/audio_recorder/audio_recording_manager.dart';
import 'package:yoloit/features/board/audio_recorder/audio_source.dart';
import 'package:yoloit/features/board/audio_recorder/pcm_wav.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';

class FakeAudioSource implements AudioSource {
  FakeAudioSource()
    : controller = StreamController<Uint8List>(sync: true);

  final StreamController<Uint8List> controller;
  bool stopped = false;

  @override
  Future<Stream<Uint8List>> start() async => controller.stream;

  @override
  Future<void> stop() async {
    stopped = true;
    if (!controller.isClosed) {
      await controller.close();
    }
  }
}

/// Source whose [start] throws, to exercise start()-time rollback.
class ThrowingStartSource implements AudioSource {
  @override
  Future<Stream<Uint8List>> start() async =>
      throw StateError('start failed');

  @override
  Future<void> stop() async {}
}

/// Source whose [stop] throws, to exercise stop()-time cleanup.
class ThrowingStopSource implements AudioSource {
  ThrowingStopSource()
    : controller = StreamController<Uint8List>(sync: true);

  final StreamController<Uint8List> controller;
  bool stopped = false;

  @override
  Future<Stream<Uint8List>> start() async => controller.stream;

  @override
  Future<void> stop() async {
    stopped = true;
    throw StateError('stop failed');
  }
}

/// In-memory [PcmSink] that records chunks and whether it was closed.
class FakeSink implements PcmSink {
  final List<Uint8List> chunks = <Uint8List>[];
  bool closed = false;

  @override
  int get dataSize => chunks.fold<int>(0, (sum, c) => sum + c.length);

  @override
  Duration get duration => Duration.zero;

  @override
  Future<void> add(Uint8List bytes) async {
    chunks.add(bytes);
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}

File _findRecording(Directory dir) {
  final files =
      dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.wav'))
          .toList();
  expect(files, hasLength(1), reason: 'expected exactly one WAV in ${dir.path}');
  return files.first;
}

void main() {
  late Directory tempDir;

  setUp(() async {
    // BoardCubit persists board state through SharedPreferences.
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('rec_mgr_test_');
  });

  tearDown(() async {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('records microphone only into a valid WAV file', () async {
    final mic = FakeAudioSource();
    final manager = AudioRecordingManager.testInstance(
      micFactory: () => mic,
      folderResolver: (_, _) async => tempDir.path,
    );

    await manager.start(panelId: 'p1', boardId: 'b1');
    expect(manager.isRecording('p1'), isTrue);
    expect(manager.activePanelIds, ['p1']);

    final micAll = pcm16Samples(<int>[100, -200, 300, -400, 500, -600]);
    mic.controller.add(pcm16Samples(<int>[100, -200, 300]));
    mic.controller.add(pcm16Samples(<int>[-400, 500, -600]));

    await manager.stop('p1');
    expect(manager.isRecording('p1'), isFalse);
    expect(mic.stopped, isTrue);

    final bytes = await _findRecording(tempDir).readAsBytes();
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    expect(bytes.sublist(44), micAll);
  });

  test('mixes microphone and system sources with clipping', () async {
    final mic = FakeAudioSource();
    final system = FakeAudioSource();
    final manager = AudioRecordingManager.testInstance(
      micFactory: () => mic,
      folderResolver: (_, _) async => tempDir.path,
    );

    await manager.start(panelId: 'p2', boardId: 'b1', systemSource: system);

    final micAll = pcm16Samples(<int>[30000, -30000, 100]);
    final sysAll = pcm16Samples(<int>[30000, -30000, 50]);
    mic.controller.add(micAll);
    system.controller.add(sysAll);

    await manager.stop('p2');

    final bytes = await _findRecording(tempDir).readAsBytes();
    final expected = mixPcm16(micAll, sysAll);
    expect(bytes.sublist(44), expected);
    // Spot-check the clipping actually happened.
    expect(readPcm16Sample(bytes.sublist(44), 0), 32767);
    expect(readPcm16Sample(bytes.sublist(44), 1), -32768);
  });

  test('start is a no-op when already recording and disposeAll stops all',
      () async {
    final mic = FakeAudioSource();
    final manager = AudioRecordingManager.testInstance(
      micFactory: () => mic,
      folderResolver: (_, _) async => tempDir.path,
    );

    await manager.start(panelId: 'p3', boardId: 'b1');
    await manager.start(panelId: 'p3', boardId: 'b1'); // ignored
    mic.controller.add(pcm16Samples(<int>[1, 2, 3]));

    await manager.disposeAll();
    expect(manager.activePanelIds, isEmpty);
    expect(mic.stopped, isTrue);
    expect(_findRecording(tempDir).existsSync(), isTrue);
  });

  group('bounded buffers', () {
    test('truncates chunks at the cap and drops the rest', () async {
      final mic = FakeAudioSource();
      final sink = FakeSink();
      final manager = AudioRecordingManager.testInstance(
        micFactory: () => mic,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
        maxSourceBufferBytes: 8,
      );

      await manager.start(panelId: 'cap', boardId: 'b1');

      // 12 bytes total, but the cap is 8: the first chunk is truncated to
      // 8 bytes and the second is dropped entirely.
      mic.controller.add(pcm16Samples(<int>[1, 2, 3, 4, 5, 6]));
      mic.controller.add(pcm16Samples(<int>[7, 8, 9, 10]));
      mic.controller.add(pcm16Samples(<int>[11, 12]));

      await manager.stop('cap');

      expect(sink.chunks, hasLength(1));
      // Buffer never grew past the cap: only the truncated prefix survives.
      expect(sink.chunks.single.length, 8);
      expect(
        List<int>.generate(4, (i) => readPcm16Sample(sink.chunks.single, i)),
        <int>[1, 2, 3, 4],
      );
      expect(sink.closed, isTrue);
    });

    test('caps each source independently when mixing', () async {
      final mic = FakeAudioSource();
      final system = FakeAudioSource();
      final sink = FakeSink();
      final manager = AudioRecordingManager.testInstance(
        micFactory: () => mic,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
        maxSourceBufferBytes: 4,
      );

      await manager.start(panelId: 'cap2', boardId: 'b1', systemSource: system);

      mic.controller.add(pcm16Samples(<int>[10, 20, 30]));
      system.controller.add(pcm16Samples(<int>[1, 2, 3]));

      await manager.stop('cap2');

      expect(sink.chunks.single.length, 4);
      expect(readPcm16Sample(sink.chunks.single, 0), 11);
      expect(readPcm16Sample(sink.chunks.single, 1), 22);
      expect(sink.closed, isTrue);
    });
  });

  group('exception paths release resources', () {
    test('a throwing source.start rolls back and closes the sink', () async {
      final sink = FakeSink();
      final manager = AudioRecordingManager.testInstance(
        micFactory: ThrowingStartSource.new,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
        folderResolver: (_, _) async => tempDir.path,
      );

      await expectLater(
        manager.start(panelId: 'boom', boardId: 'b1'),
        throwsA(isA<StateError>()),
      );

      // No stranded entry, no stranded sink.
      expect(manager.isRecording('boom'), isFalse);
      expect(manager.activePanelIds, isEmpty);
      expect(sink.closed, isTrue);

      // The manager is still usable afterwards.
      final mic = FakeAudioSource();
      final manager2 = AudioRecordingManager.testInstance(
        micFactory: () => mic,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
        folderResolver: (_, _) async => tempDir.path,
      );
      await manager2.start(panelId: 'ok', boardId: 'b1');
      mic.controller.add(pcm16Samples(<int>[5]));
      await manager2.stop('ok');
      expect(sink.closed, isTrue);
    });

    test('a throwing source.stop still closes the sink and removes the entry',
        () async {
      final mic = FakeAudioSource();
      final system = ThrowingStopSource();
      final sink = FakeSink();
      final manager = AudioRecordingManager.testInstance(
        micFactory: () => mic,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
        folderResolver: (_, _) async => tempDir.path,
      );

      await manager.start(panelId: 'p-throw', boardId: 'b1', systemSource: system);
      mic.controller.add(pcm16Samples(<int>[100, 200]));
      system.controller.add(pcm16Samples(<int>[1, 2]));

      // Must not throw even though system.stop() fails.
      await manager.stop('p-throw');

      // Both sources were stopped (the healthy one too), entry removed,
      // sink finalized with the mixed data.
      expect(mic.stopped, isTrue);
      expect(system.stopped, isTrue);
      expect(manager.isRecording('p-throw'), isFalse);
      expect(sink.closed, isTrue);
      expect(sink.chunks, hasLength(1));
      expect(readPcm16Sample(sink.chunks.single, 0), 101);
      expect(readPcm16Sample(sink.chunks.single, 1), 202);
    });
  });

  group('default folder resolver and panel lookup', () {
    final createdFiles = <File>[];

    tearDown(() async {
      for (final file in createdFiles) {
        try {
          if (await file.exists()) await file.delete();
        } on FileSystemException {
          // Best-effort cleanup.
        }
      }
      createdFiles.clear();
      // Remove the system-temp fallback dir only when the test left it empty.
      final fallback = Directory(
        '${Directory.systemTemp.path}${Platform.pathSeparator}yoloit_recordings',
      );
      try {
        if (await fallback.exists() && (await fallback.list().isEmpty)) {
          await fallback.delete();
        }
      } on FileSystemException {
        // Not empty or already gone — leave it alone.
      }
    });

    /// Starts and stops a recording through the real default folder resolver,
    /// returning the path of the WAV file the manager opened.
    Future<String> recordIntoDefaultFolder({
      BoardCubit? cubit,
      String panelId = 'p1',
      String boardId = 'b1',
    }) async {
      String? openedPath;
      final manager = AudioRecordingManager.testInstance(
        micFactory: FakeAudioSource.new,
        openSink: (file, {format = const PcmWavFormat()}) {
          openedPath = file.path;
          return PcmWavSink.create(file, format: format);
        },
      );
      if (cubit != null) manager.setCubit(cubit);
      await manager.start(panelId: panelId, boardId: boardId);
      await manager.stop(panelId);
      final path = openedPath;
      expect(path, isNotNull, reason: 'the sink opener should be called');
      createdFiles.add(File(path!));
      return path;
    }

    BoardPanelInstance panel(
      String id, {
      AudioRecorderConfig config = const AudioRecorderConfig(),
    }) =>
        BoardPanelInstance(
          id: id,
          type: 'board.audio_recorder',
          title: 'Recorder',
          bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: <String, dynamic>{AudioRecorderConfig.configKey: config.toJson()},
        );

    BoardDocument board(
      String id, {
      List<BoardPanelInstance> panels = const [],
      String defaultFolder = '',
    }) =>
        BoardDocument(
          id: id,
          name: id,
          panels: panels,
          metadata: <String, dynamic>{'defaultFolder': defaultFolder},
        );

    BoardCubit cubitWith(List<BoardDocument> boards, String activeId) {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(BoardState(boards: boards, activeBoardId: activeId, isLoaded: true));
      return cubit;
    }

    test('uses the configured saveFolder from the panel on the named board',
        () async {
      final cubit = cubitWith([
        board('b1', panels: [
          panel('p1', config: AudioRecorderConfig(saveFolder: tempDir.path)),
        ]),
      ], 'b1');

      final path = await recordIntoDefaultFolder(cubit: cubit);
      expect(path, startsWith(tempDir.path));
    });

    test('falls back to the board defaultFolder when nothing is configured',
        () async {
      final cubit = cubitWith([
        board('b1', panels: [panel('p1')], defaultFolder: tempDir.path),
      ], 'b1');

      final path = await recordIntoDefaultFolder(cubit: cubit);
      expect(
        path,
        startsWith('${tempDir.path}${Platform.pathSeparator}recordings'),
      );
    });

    test('uses the active board when the named board is unknown', () async {
      final cubit = cubitWith([
        board('b-active', panels: [panel('p1')], defaultFolder: tempDir.path),
      ], 'b-active');

      final path = await recordIntoDefaultFolder(cubit: cubit, boardId: 'b-gone');
      expect(
        path,
        startsWith('${tempDir.path}${Platform.pathSeparator}recordings'),
      );
    });

    test('reads the config from another board when the panel moved', () async {
      final cubit = cubitWith([
        board('b1'),
        board('b2', panels: [
          panel('p1', config: AudioRecorderConfig(saveFolder: tempDir.path)),
        ]),
      ], 'b1');

      // p1 lives on b2 but the caller claims b1: the second scan finds it.
      final path = await recordIntoDefaultFolder(cubit: cubit);
      expect(path, startsWith(tempDir.path));
    });

    test('falls back to a system-temp folder when the board has no default',
        () async {
      final cubit = cubitWith([board('b1')], 'b1');

      final path = await recordIntoDefaultFolder(cubit: cubit);
      expect(path, contains('yoloit_recordings'));
    });

    test('falls back to a system-temp folder without an attached cubit',
        () async {
      final path = await recordIntoDefaultFolder();
      expect(path, contains('yoloit_recordings'));
    });
  });

  group('board visibility gating', () {
    BoardPanelInstance panel() => const BoardPanelInstance(
      id: 'p1',
      type: 'board.audio_recorder',
      title: 'Recorder',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
    );

    BoardDocument board(String id, {List<BoardPanelInstance> panels = const []}) =>
        BoardDocument(id: id, name: id, panels: panels);

    BoardPanelInstance panelOn(BoardCubit cubit, String boardId) => cubit
        .state
        .boards
        .firstWhere((b) => b.id == boardId)
        .panels
        .singleWhere((p) => p.id == 'p1');

    test('skips progress writes while hidden and self-corrects on return',
        () async {
      final mic = FakeAudioSource();
      final sink = FakeSink();
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(
        BoardState(
          boards: [board('b1', panels: [panel()]), board('b2')],
          activeBoardId: 'b2',
          isLoaded: true,
        ),
      );
      late final AudioRecordingManager manager;

      fakeAsync((async) {
        // fakeAsync fakes timers, not the wall clock — drive the manager's
        // clock from the fake zone.
        final clock = async.getClock(DateTime(2024));
        manager = AudioRecordingManager.testInstance(
          micFactory: () => mic,
          openSink: (_, {format = const PcmWavFormat()}) async => sink,
          now: clock.now,
        );
        manager.setCubit(cubit);

        manager.start(panelId: 'p1', boardId: 'b1');
        async.flushMicrotasks();

        // ~8 hidden ticks (4/sec): none of them may touch the panel state.
        async.elapse(const Duration(seconds: 2));
        final hiddenPanel = panelOn(cubit, 'b1');
        expect(hiddenPanel.state['isRecording'], isNot(true));
        expect(hiddenPanel.state.containsKey('elapsedMs'), isFalse);

        // Board becomes visible: the next tick writes exactly once and the
        // elapsed time covers the hidden period too.
        cubit.emit(cubit.state.copyWith(activeBoardId: 'b1'));
        async.elapse(const Duration(milliseconds: 300));

        final visiblePanel = panelOn(cubit, 'b1');
        expect(visiblePanel.state['isRecording'], isTrue);
        final elapsedMs = visiblePanel.state['elapsedMs'];
        expect(elapsedMs, isA<int>());
        // ~2.25s of recording: accumulated while hidden + one visible tick.
        expect(elapsedMs as int, greaterThanOrEqualTo(2000));
        expect(elapsedMs, lessThan(2300));
      });

      await manager.stop('p1');

      expect(manager.isRecording('p1'), isFalse);
      expect(mic.stopped, isTrue);
      expect(sink.closed, isTrue);
    });

    test('stop while hidden still lands the finished recording entry',
        () async {
      final mic = FakeAudioSource();
      final sink = FakeSink();
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      cubit.emit(
        BoardState(
          boards: [board('b1', panels: [panel()]), board('b2')],
          activeBoardId: 'b2',
          isLoaded: true,
        ),
      );
      final manager = AudioRecordingManager.testInstance(
        micFactory: () => mic,
        openSink: (_, {format = const PcmWavFormat()}) async => sink,
      );
      manager.setCubit(cubit);

      fakeAsync((async) {
        manager.start(panelId: 'p1', boardId: 'b1');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 1));

        mic.controller.add(pcm16Samples(<int>[7, 8]));
      });

      // Stop from a hidden board: the completion write must still land so
      // the recording appears once the board returns.
      await manager.stop('p1');

      final finished = panelOn(cubit, 'b1');
      expect(finished.state['isRecording'], isFalse);
      expect(finished.state['elapsedMs'], 0);
      final recordings =
          (finished.state['recordings'] as List<dynamic>?) ?? const [];
      expect(recordings, hasLength(1));
      expect(recordings.single, isA<Map<String, dynamic>>());
      expect((recordings.single as Map<String, dynamic>)['format'], 'wav');
      expect(sink.closed, isTrue);
      expect(manager.isRecording('p1'), isFalse);
    });
  });
}
