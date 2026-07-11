import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/system_audio_bridge.dart';
import 'package:yoloit/features/board/audio_recorder/system_audio_source.dart';

class FakeBridge implements SystemAudioBridge {
  bool supported = true;
  bool started = false;
  bool stopped = false;
  int? lastSampleRate;
  int? lastChannels;
  // ignore: close_sinks
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>(sync: true);

  @override
  bool get isSupported => supported;

  @override
  Future<String> status() async => 'authorized';

  @override
  Future<bool> request() async => true;

  @override
  Future<bool> openSettings() async => true;

  @override
  Future<void> startCapture({
    required int sampleRate,
    required int channels,
  }) async {
    started = true;
    lastSampleRate = sampleRate;
    lastChannels = channels;
  }

  @override
  Future<void> stopCapture() async {
    stopped = true;
  }

  @override
  Stream<Uint8List> pcmStream() => controller.stream;
}

void main() {
  test('start begins capture and returns the PCM stream at 48 kHz / stereo',
      () async {
    final bridge = FakeBridge();
    final source = SystemAudioSource(bridge: bridge);

    final stream = await source.start();

    expect(bridge.started, isTrue);
    expect(bridge.lastSampleRate, 48000);
    expect(bridge.lastChannels, 2);

    final received = <Uint8List>[];
    final sub = stream.listen(received.add);
    final chunk = Uint8List.fromList(<int>[1, 2, 3, 4]);
    bridge.controller.add(chunk);
    await Future<void>.delayed(Duration.zero);
    expect(received, [chunk]);

    await source.stop();
    expect(bridge.stopped, isTrue);
    await sub.cancel();
    await bridge.controller.close();
  });

  test('start throws when the bridge is unsupported', () async {
    final bridge = FakeBridge()..supported = false;
    final source = SystemAudioSource(bridge: bridge);
    expect(source.start, throwsUnsupportedError);
  });
}
