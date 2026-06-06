import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/microphone_permission_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MicrophonePermissionService', () {
    const channel = MethodChannel('yoloit/microphone_permission');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        switch (call.method) {
          case 'status':
            return 'authorized';
          case 'bundleIdentifier':
            return 'com.test.app';
          case 'displayName':
            return 'TestApp';
          case 'request':
            return true;
          case 'openSettings':
            return true;
          default:
            return null;
        }
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('status returns mocked value on macOS', () async {
      if (!Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.status();
      expect(result, 'authorized');
    });

    test('bundleIdentifier returns mocked value on macOS', () async {
      if (!Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.bundleIdentifier();
      expect(result, 'com.test.app');
    });

    test('displayName returns mocked value on macOS', () async {
      if (!Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.displayName();
      expect(result, 'TestApp');
    });

    test('ensureGranted returns true when mock returns true', () async {
      if (!Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.ensureGranted();
      expect(result, isTrue);
    });

    test('openSettings returns true when mock returns true', () async {
      if (!Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.openSettings();
      expect(result, isTrue);
    });

    test('status returns authorized on non-macOS', () async {
      if (Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.status();
      expect(result, 'authorized');
    });

    test('bundleIdentifier returns yoloit on non-macOS', () async {
      if (Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.bundleIdentifier();
      expect(result, 'yoloit');
    });

    test('displayName returns YoLoIT on non-macOS', () async {
      if (Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.displayName();
      expect(result, 'YoLoIT');
    });

    test('ensureGranted returns true on non-macOS', () async {
      if (Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.ensureGranted();
      expect(result, isTrue);
    });

    test('openSettings returns false on non-macOS', () async {
      if (Platform.isMacOS) return;
      final result = await MicrophonePermissionService.instance.openSettings();
      expect(result, isFalse);
    });
  });
}
