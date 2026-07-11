import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/system_audio_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SystemAudioBridge (native)', () {
    const channel = MethodChannel('yoloit/system_audio');
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'status':
                return 'authorized';
              case 'request':
                return true;
              case 'openSettings':
                return true;
              case 'start':
              case 'stop':
                return null;
              default:
                return null;
            }
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('status/request/openSettings invoke the channel on macOS', () async {
      if (!Platform.isMacOS) return;
      final bridge = SystemAudioBridge.instance;
      expect(await bridge.status(), 'authorized');
      expect(await bridge.request(), isTrue);
      expect(await bridge.openSettings(), isTrue);
      expect(
        calls.map((c) => c.method),
        containsAll(<String>['status', 'request', 'openSettings']),
      );
    });

    test('startCapture forwards the PCM format on macOS', () async {
      if (!Platform.isMacOS) return;
      await SystemAudioBridge.instance.startCapture(
        sampleRate: 48000,
        channels: 2,
      );
      final start = calls.firstWhere((c) => c.method == 'start');
      final args = Map<String, dynamic>.from(start.arguments as Map);
      expect(args['sampleRate'], 48000);
      expect(args['channels'], 2);

      await SystemAudioBridge.instance.stopCapture();
      expect(calls.map((c) => c.method), contains('stop'));
    });

    test('short-circuits on non-macOS', () async {
      if (Platform.isMacOS) return;
      final bridge = SystemAudioBridge.instance;
      expect(bridge.isSupported, isFalse);
      expect(await bridge.status(), 'authorized');
      expect(await bridge.request(), isTrue);
      expect(await bridge.openSettings(), isFalse);
      expect(
        () => bridge.startCapture(sampleRate: 48000, channels: 2),
        throwsUnsupportedError,
      );
    });
  });
}
