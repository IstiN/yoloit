import 'dart:io';

import 'package:flutter/foundation.dart';

/// Installed `yoloit` CLI wrapper paths (debug vs release config dirs).
abstract final class CliInstalledPaths {
  /// Debug → `~/.config/yoloit-dev` (separate port/state).
  /// Release → `~/.config/yoloit`.
  static String configDirForHome(String home) => kDebugMode
      ? '$home/.config/yoloit-dev'
      : '$home/.config/yoloit';

  /// Debug → `~/.config/yoloit-dev/yoloit-debug` (separate port/state).
  /// Release → `~/.config/yoloit/yoloit`.
  static String pathForHome(String home) => '${configDirForHome(home)}/yoloit${kDebugMode ? '-debug' : ''}';

  /// Returns the installed CLI wrapper when present for the current mode.
  static File? executable() {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isEmpty) return null;
    final file = File(pathForHome(home));
    return file.existsSync() ? file : null;
  }
}
