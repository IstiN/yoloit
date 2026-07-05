import 'dart:io';

import 'package:yoloit/core/platform/platform_dirs.dart';

PlatformDirs createPlatformDirs() {
  if (Platform.isIOS) return const IosPlatformDirs();
  if (Platform.isMacOS) return const MacosPlatformDirs();
  if (Platform.isLinux) return const LinuxPlatformDirs();
  if (Platform.isWindows) return const WindowsPlatformDirs();
  // Fallback — treat like Linux.
  return const LinuxPlatformDirs();
}

/// macOS paths — matches the values previously hardcoded across the codebase.
///
/// Config:  `~/.config/yoloit/`   (matches legacy hardcoded value)
/// Logs:    `~/Library/Logs/yoloit/`
/// Data:    `~/Library/Application Support/yoloit/`
class MacosPlatformDirs extends PlatformDirs {
  const MacosPlatformDirs({String? homeOverride})
    : _homeOverride = homeOverride;

  final String? _homeOverride;

  String get _home => _homeOverride ?? Platform.environment['HOME'] ?? '/tmp';

  @override
  String get configDir => '$_home/.config/yoloit';

  @override
  String get dataDir => '$_home/Library/Application Support/yoloit';

  @override
  String get logsDir => '$_home/Library/Logs/yoloit';

  @override
  String get tempDir => Directory.systemTemp.path;

  @override
  String get skillsDir => '$_home/.config/yoloit/skills';

  @override
  String get yoloitTempDir => '${Directory.systemTemp.path}/yoloit_tmp';
}

/// iOS paths — all persistent files live inside the app sandbox.
///
/// Config/Data: `<sandbox>/Documents/yoloit/`
/// Logs:        `<sandbox>/Documents/yoloit/logs/`
class IosPlatformDirs extends PlatformDirs {
  const IosPlatformDirs({String? homeOverride}) : _homeOverride = homeOverride;

  final String? _homeOverride;

  String get _home => _homeOverride ?? Platform.environment['HOME'] ?? '/tmp';

  String get _root => '$_home/Documents/yoloit';

  @override
  String get configDir => _root;

  @override
  String get dataDir => _root;

  @override
  String get logsDir => '$_root/logs';

  @override
  String get tempDir => Directory.systemTemp.path;

  @override
  String get skillsDir => '$_root/skills';

  @override
  String get yoloitTempDir => '${Directory.systemTemp.path}/yoloit_tmp';
}

/// Linux paths — follows XDG Base Directory conventions.
///
/// Config:  `~/.config/yoloit/`
/// Data:    `~/.local/share/yoloit/`
/// Logs:    `~/.local/share/yoloit/logs/`
class LinuxPlatformDirs extends PlatformDirs {
  const LinuxPlatformDirs({String? homeOverride})
    : _homeOverride = homeOverride;

  final String? _homeOverride;

  String get _home => _homeOverride ?? Platform.environment['HOME'] ?? '/tmp';

  @override
  String get configDir => '$_home/.config/yoloit';

  @override
  String get dataDir => '$_home/.local/share/yoloit';

  @override
  String get logsDir => '$_home/.local/share/yoloit/logs';

  @override
  String get tempDir => Directory.systemTemp.path;

  @override
  String get skillsDir => '$_home/.config/yoloit/skills';

  @override
  String get yoloitTempDir => '${Directory.systemTemp.path}/yoloit_tmp';
}

/// Windows paths — follows AppData conventions.
///
/// Config:  `%APPDATA%\yoloit\`
/// Data:    `%APPDATA%\yoloit\`
/// Logs:    `%APPDATA%\yoloit\logs\`
class WindowsPlatformDirs extends PlatformDirs {
  const WindowsPlatformDirs({String? appDataOverride})
    : _appDataOverride = appDataOverride;

  final String? _appDataOverride;

  String get _appData =>
      _appDataOverride ??
      Platform.environment['APPDATA'] ??
      Platform.environment['USERPROFILE'] ??
      'C:\\Users\\Default\\AppData\\Roaming';

  @override
  String get configDir => '$_appData\\yoloit';

  @override
  String get dataDir => '$_appData\\yoloit';

  @override
  String get logsDir => '$_appData\\yoloit\\logs';

  @override
  String get tempDir =>
      Platform.environment['TEMP'] ??
      Platform.environment['TMP'] ??
      'C:\\Windows\\Temp';

  @override
  String get skillsDir => '$_appData\\yoloit\\skills';

  @override
  String get yoloitTempDir => '${Directory.systemTemp.path}\\yoloit_tmp';
}
