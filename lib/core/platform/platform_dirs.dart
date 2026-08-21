import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:yoloit/core/platform/platform_dirs_factory.dart' as impl;

export 'package:yoloit/core/platform/platform_dirs_vm.dart'
  if (dart.library.html) 'package:yoloit/core/platform/platform_dirs_web.dart';

/// Platform-aware directory paths for YoLoIT config, data, logs and temp.
///
/// All paths are consistent with platform conventions and match the values
/// that were previously hardcoded across the codebase.
///
/// The implementation is selected via conditional export, so the web build
/// receives a stub that does not depend on `dart:io`.
///
/// Usage:
/// ```dart
/// final dirs = PlatformDirs.instance;
/// final configPath = '${dirs.configDir}/agent_configs.json';
/// ```
abstract class PlatformDirs {
  const PlatformDirs();

  /// Singleton — picks the right implementation based on the current runtime.
  static PlatformDirs? _instance;
  static PlatformDirs get instance {
    _instance ??= impl.createPlatformDirs();
    return _instance!;
  }

  /// Override the singleton (useful for testing).
  // ignore: use_setters_to_change_properties
  static void setInstance(PlatformDirs instance) => _instance = instance;

  /// Resets the cached instance so the next [instance] call re-evaluates.
  @visibleForTesting
  static void reset() => _instance = null;

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
  String get yoloitTempDir;

  /// User home directory (e.g. `/Users/alice` on macOS, `/home/alice` on
  /// Linux, `C:\Users\alice` on Windows). Returns `null` on platforms where
  /// the concept doesn't apply (e.g. web build).
  String? get userHome;
}
