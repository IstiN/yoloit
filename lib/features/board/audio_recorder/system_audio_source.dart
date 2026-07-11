import 'dart:typed_data';

import 'package:yoloit/core/platform/system_audio_bridge.dart';
import 'package:yoloit/features/board/audio_recorder/audio_source.dart';

/// System/loopback audio source backed by the macOS ScreenCaptureKit plugin.
///
/// Delegates to [SystemAudioBridge]; inject a fake bridge in tests.
class SystemAudioSource implements AudioSource {
  SystemAudioSource({SystemAudioBridge? bridge})
    : _bridge = bridge ?? SystemAudioBridge.instance;

  final SystemAudioBridge _bridge;

  @override
  Future<Stream<Uint8List>> start() async {
    if (!_bridge.isSupported) {
      throw UnsupportedError('System audio capture requires macOS 14+.');
    }
    await _bridge.startCapture(sampleRate: 48000, channels: 2);
    return _bridge.pcmStream();
  }

  @override
  Future<void> stop() => _bridge.stopCapture();
}
