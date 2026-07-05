import 'dart:io';

String get currentPlatformName {
  if (Platform.isIOS) return 'ios';
  if (Platform.isMacOS) return 'macos';
  if (Platform.isLinux) return 'linux';
  if (Platform.isWindows) return 'windows';
  if (Platform.isAndroid) return 'android';
  return 'unknown';
}
