import 'dart:typed_data';

import 'package:record/record.dart';

/// A source of raw interleaved 16-bit little-endian PCM audio at the recorder's
/// canonical format (48 kHz / stereo).
///
/// Implementations wrap the microphone (`record`) and, in Slice 3, the macOS
/// system-audio loopback (ScreenCaptureKit). The manager mixes any number of
/// these sources into one WAV file.
abstract class AudioSource {
  /// Starts capturing and returns the PCM byte stream.
  Future<Stream<Uint8List>> start();

  /// Stops capturing and releases the underlying device.
  Future<void> stop();
}

/// Microphone source backed by the `record` plugin.
///
/// Permission must be granted by the caller (see
/// `MicrophonePermissionService`) before [start] is invoked.
class RecordMicSource implements AudioSource {
  AudioRecorder? _recorder;

  @override
  Future<Stream<Uint8List>> start() async {
    final recorder = AudioRecorder();
    _recorder = recorder;
    return recorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 48000,
        numChannels: 2,
      ),
    );
  }

  @override
  Future<void> stop() async {
    final recorder = _recorder;
    _recorder = null;
    if (recorder == null) return;
    await recorder.stop();
    await recorder.dispose();
  }
}
