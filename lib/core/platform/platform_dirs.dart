import 'dart:io';

/// Platform-aware directory paths for YoLoIT config, data, logs and temp.
///
/// All paths are consistent with platform conventions and match the values
/// that were previously hardcoded across the codebase.
///
/// Usage:
/// ```dart
/// final dirs = PlatformDirs.instance;
/// final configPath = '${dirs.configDir}/agent_configs.json';
/// ```
abstract class PlatformDirs {
  const PlatformDirs();

  /// Singleton — picks the right implementation based on the current OS.
  static PlatformDirs? _instance;
  static PlatformDirs get instance {
    _instance ??= _create();
    return _instance!;
  }

  /// Override the singleton (useful for testing).
  // ignore: use_setters_to_change_properties
  static void setInstance(PlatformDirs instance) => _instance = instance;

  static PlatformDirs _create() {
    if (Platform.isMacOS) return const MacosPlatformDirs();
    if (Platform.isLinux) return const LinuxPlatformDirs();
    if (Platform.isWindows) return const WindowsPlatformDirs();
    // Fallback — treat like Linux.
    return const LinuxPlatformDirs();
  }

  /// Directory for persistent configuration files (e.g. agent_configs.json).
  String get configDir;

  /// Directory for persistent application data.
  String get dataDir;

  /// Directory for log files.
  String get logsDir;

  /// System temp directory (suitable for short-lived files).
  String get tempDir;

  /// Directory for globally installed skills (~/.config/yoloit/skills/).
  String get skillsDir;

  /// Convenience: a dedicated YoLoIT temp sub-directory.
  String get yoloitTempDir => '${Directory.systemTemp.path}/yoloit_tmp';
}

// ── macOS ────────────────────────────────────────────────────────────────────

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
}

// ── Linux ────────────────────────────────────────────────────────────────────

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
}

// ── Windows ──────────────────────────────────────────────────────────────────

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
