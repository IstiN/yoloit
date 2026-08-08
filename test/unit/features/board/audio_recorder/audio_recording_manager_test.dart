import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

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
}
