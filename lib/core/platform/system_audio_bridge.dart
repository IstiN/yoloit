import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

/// Bridge to the native system-audio (loopback) capture.
///
/// On macOS 14+ this talks to the ScreenCaptureKit-backed plugin over the
/// `yoloit/system_audio` method channel and the `yoloit/system_audio_pcm` event
/// channel (raw interleaved 16-bit little-endian PCM). On every other platform
/// the methods short-circuit so feature code never touches the channels.
abstract class SystemAudioBridge {
  static SystemAudioBridge _instance = const _NativeSystemAudioBridge();

  static SystemAudioBridge get instance => _instance;

  @visibleForTesting
  static set instance(SystemAudioBridge value) => _instance = value;

  /// Whether native loopback capture can work on this runtime (macOS only).
  bool get isSupported;

  /// Screen-recording permission status: `authorized`, `denied`,
  /// `notDetermined` or `unknown`.
  Future<String> status();

  /// Triggers the system permission prompt. Returns true if authorized.
  Future<bool> request();

  /// Opens System Settings on the Screen Recording pane. Returns true if opened.
  Future<bool> openSettings();

  /// Starts capture of system audio at the given PCM format.
  Future<void> startCapture({required int sampleRate, required int channels});

  /// Stops capture.
  Future<void> stopCapture();

  /// Stream of raw interleaved 16-bit little-endian PCM chunks produced by the
  /// native side. Valid after [startCapture].
  Stream<Uint8List> pcmStream();
}

class _NativeSystemAudioBridge implements SystemAudioBridge {
  const _NativeSystemAudioBridge();

  static const MethodChannel _channel = MethodChannel('yoloit/system_audio');
  static const EventChannel _pcmChannel = EventChannel(
    'yoloit/system_audio_pcm',
  );

  @override
  bool get isSupported => Platform.isMacOS;

  @override
  Future<String> status() async {
    if (!Platform.isMacOS) return 'authorized';
    return await _channel.invokeMethod<String>('status') ?? 'unknown';
  }

  @override
  Future<bool> request() async {
    if (!Platform.isMacOS) return true;
    return await _channel.invokeMethod<bool>('request') ?? false;
  }

  @override
  Future<bool> openSettings() async {
    if (!Platform.isMacOS) return false;
    return await _channel.invokeMethod<bool>('openSettings') ?? false;
  }

  @override
  Future<void> startCapture({
    required int sampleRate,
    required int channels,
  }) async {
    if (!Platform.isMacOS) {
      throw UnsupportedError('System audio capture requires macOS 14+.');
    }
    await _channel.invokeMethod<void>('start', <String, dynamic>{
      'sampleRate': sampleRate,
      'channels': channels,
    });
  }

  @override
  Future<void> stopCapture() async {
    if (!Platform.isMacOS) return;
    await _channel.invokeMethod<void>('stop');
  }

  @override
  Stream<Uint8List> pcmStream() {
    return _pcmChannel.receiveBroadcastStream().map((event) {
      if (event is Uint8List) return event;
      if (event is List) {
        return Uint8List.fromList(event.cast<int>());
      }
      throw StateError('Unexpected PCM event type: ${event.runtimeType}');
    });
  }
}
