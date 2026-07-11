import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/audio_recorder/audio_recording_manager.dart';
import 'package:yoloit/features/board/audio_recorder/audio_source.dart';
import 'package:yoloit/features/board/audio_recorder/pcm_wav.dart';

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
}
