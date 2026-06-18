import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

/// Shared YoLoIT daemon (yoloitd) state directory for port/pid files.
///
/// Must match [RuntimeTerminalClient] so resource monitoring and terminal
/// sessions talk to the same yoloitd instance.
class RuntimePaths {
  RuntimePaths._();

  static String get home {
    if (kDebugMode) {
      final homeDir =
          Platform.environment['HOME'] ??
          Platform.environment['USERPROFILE'] ??
          Directory.systemTemp.path;
      return '$homeDir/.config/yoloit-dev/runtime';
    }
    return '${PlatformDirs.instance.configDir}/runtime';
  }

  static String get portFile => '$home/runtime.port';

  static String get pidFile => '$home/runtime.pid';
}
