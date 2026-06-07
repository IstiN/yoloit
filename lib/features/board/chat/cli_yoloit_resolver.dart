import 'dart:io';

import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/utils/yoloit_bin_resolver.dart';

/// Resolves the `yoloit` CLI binary path and builds enriched PATH strings
/// for CLI providers that need to expose YoLoIT commands to sub-processes
/// (e.g. Copilot, OpenCode).
class CliYoloitResolver {
  CliYoloitResolver._();

  static String? _cached;

  /// Clear the cached bin path so the next call re-resolves from disk.
  static void clearCache() => _cached = null;

  /// Find the `yoloit` executable, preferring the installed location
  /// (`~/.config/yoloit/yoloit`) and falling back to a search up the
  /// directory tree from the current working directory.
  static String? resolve() {
    final cached = _cached;
    if (cached != null && File(cached).existsSync()) return cached;

    final result = resolveYoloitBin(maxDepth: 6);
    _cached = result;
    return result;
  }

  /// Build a session PATH that prepends the directory containing [yoloitBin]
  /// to the enriched shell PATH.
  static String buildSessionPath(
    String existingPath, {
    required String? yoloitBin,
  }) {
    final shell = PlatformShell.instance;
    final entries = <String>[
      if (yoloitBin != null) File(yoloitBin).parent.path,
      ...shell.splitPath(shell.enrichedPath(existingPath)),
    ];
    final deduped = <String>[];
    for (final entry in entries) {
      if (entry.isEmpty || deduped.contains(entry)) continue;
      deduped.add(entry);
    }
    return shell.joinPath(deduped);
  }
}
