import 'dart:io';

/// Platform-aware shell selection and PATH enrichment.
///
/// Unifies the `_enrichedPath()` logic that was previously duplicated in
/// `pty_service.dart`, `run_service.dart`, and `setup_check_service.dart`.
///
/// Usage:
/// ```dart
/// final shell = PlatformShell.instance;
/// final env = {
///   'SHELL': shell.defaultShell,
///   'PATH': shell.enrichedPath(Platform.environment['PATH'] ?? ''),
/// };
/// ```
abstract class PlatformShell {
  const PlatformShell();

  /// Singleton — picks the right implementation based on the current OS.
  static PlatformShell? _instance;
  static PlatformShell get instance {
    _instance ??= _create();
    return _instance!;
  }

  /// Override the singleton (useful for testing).
  // ignore: use_setters_to_change_properties
  static void setInstance(PlatformShell instance) => _instance = instance;

  static PlatformShell _create() {
    if (Platform.isMacOS) return const MacosPlatformShell();
    if (Platform.isLinux) return const LinuxPlatformShell();
    if (Platform.isWindows) return const WindowsPlatformShell();
    return const LinuxPlatformShell();
  }

  /// Default shell executable path.
  String get defaultShell;

  /// PATH separator character (`:` on Unix, `;` on Windows).
  String get pathSeparator;

  /// Builds an enriched PATH by prepending platform-specific tool directories
  /// to the [existing] PATH string. Deduplicates entries.
  String enrichedPath(String existing);

  /// Splits a PATH string by the platform separator.
  List<String> splitPath(String path) => path.split(pathSeparator);

  /// Joins path entries using the platform separator.
  String joinPath(List<String> entries) => entries.join(pathSeparator);
}

// ── macOS ────────────────────────────────────────────────────────────────────

/// macOS shell configuration — zsh with Homebrew and Flutter paths.
class MacosPlatformShell extends PlatformShell {
  const MacosPlatformShell({String? homeOverride})
      : _homeOverride = homeOverride;

  final String? _homeOverride;

  String get _home => _homeOverride ?? Platform.environment['HOME'] ?? '';

  @override
  String get defaultShell =>
      Platform.environment['SHELL'] ?? '/bin/zsh';

  @override
  String get pathSeparator => ':';

  @override
  String enrichedPath(String existing) {
    final extras = <String>[
      if (_home.isNotEmpty) '$_home/.config/yoloit',
      if (_home.isNotEmpty) '$_home/.opencode/bin',
      if (_home.isNotEmpty) '$_home/.local/bin',
      if (_home.isNotEmpty) '$_home/development/flutter/bin',
      if (_home.isNotEmpty) '$_home/flutter/bin',
      '/opt/homebrew/bin',
      '/opt/homebrew/sbin',
      '/usr/local/bin',
    ];
    return _merge(extras, existing, pathSeparator);
  }
}

// ── Linux ────────────────────────────────────────────────────────────────────

/// Linux shell configuration — bash with XDG-compliant tool paths.
class LinuxPlatformShell extends PlatformShell {
  const LinuxPlatformShell({String? homeOverride})
      : _homeOverride = homeOverride;

  final String? _homeOverride;

  String get _home => _homeOverride ?? Platform.environment['HOME'] ?? '';

  @override
  String get defaultShell =>
      Platform.environment['SHELL'] ?? '/bin/bash';

  @override
  String get pathSeparator => ':';

  @override
  String enrichedPath(String existing) {
    final extras = <String>[
      if (_home.isNotEmpty) '$_home/.config/yoloit',
      if (_home.isNotEmpty) '$_home/.local/bin',
      '/usr/local/bin',
      '/snap/bin',
    ];
    return _merge(extras, existing, pathSeparator);
  }
}

// ── Windows ──────────────────────────────────────────────────────────────────

/// Windows shell configuration — cmd.exe with semicolon PATH separator.
class WindowsPlatformShell extends PlatformShell {
  const WindowsPlatformShell({String? userProfileOverride})
      : _userProfileOverride = userProfileOverride;

  final String? _userProfileOverride;

  String get _userProfile =>
      _userProfileOverride ??
      Platform.environment['USERPROFILE'] ??
      'C:\\Users\\Default';

  @override
  String get defaultShell =>
      Platform.environment['ComSpec'] ?? 'cmd.exe';

  @override
  String get pathSeparator => ';';

  @override
  String enrichedPath(String existing) {
    final extras = <String>[
      '$_userProfile\\AppData\\Local\\Programs\\flutter\\bin',
      '$_userProfile\\AppData\\Local\\Programs\\Git\\bin',
    ];
    return _merge(extras, existing, pathSeparator);
  }
}

// ── Helpers ──────────────────────────────────────────────────────────────────

/// Prepends [extras] to [existing] PATH, deduplicating entries.
String _merge(List<String> extras, String existing, String sep) {
  final existingEntries =
      existing.split(sep).where((e) => e.isNotEmpty).toList();
  final merged = <String>[];
  for (final e in extras) {
    if (!existingEntries.contains(e) && !merged.contains(e)) merged.add(e);
  }
  merged.addAll(existingEntries);
  return merged.join(sep);
}
