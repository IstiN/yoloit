import 'dart:io';

import 'package:flutter/services.dart';

class MicrophonePermissionService {
  MicrophonePermissionService._();

  static const MethodChannel _channel = MethodChannel(
    'yoloit/microphone_permission',
  );

  static final MicrophonePermissionService instance =
      MicrophonePermissionService._();

  Future<String> status() async {
    if (!Platform.isMacOS) {
      return 'authorized';
    }
    return await _channel.invokeMethod<String>('status') ?? 'unknown';
  }

  Future<String> bundleIdentifier() async {
    if (!Platform.isMacOS) {
      return 'yoloit';
    }
    return await _channel.invokeMethod<String>('bundleIdentifier') ?? 'unknown';
  }

  Future<String> displayName() async {
    if (!Platform.isMacOS) {
      return 'YoLoIT';
    }
    return await _channel.invokeMethod<String>('displayName') ?? 'YoLoIT';
  }

  Future<bool> ensureGranted() async {
    if (!Platform.isMacOS) {
      return true;
    }
    final granted = await _channel.invokeMethod<bool>('request');
    return granted ?? false;
  }

  Future<bool> openSettings() async {
    if (!Platform.isMacOS) {
      return false;
    }
    final opened = await _channel.invokeMethod<bool>('openSettings');
    return opened ?? false;
  }
}
