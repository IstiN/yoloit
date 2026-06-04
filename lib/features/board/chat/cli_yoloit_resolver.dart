import 'dart:io';

import 'package:yoloit/core/platform/platform_shell.dart';

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

    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty) {
      final installed = File('$home/.config/yoloit/yoloit');
      if (installed.existsSync()) {
        _cached = installed.path;
        return installed.path;
      }
    }

    final roots = <Directory>[];
    void addRoot(String path) {
      if (path.isEmpty) return;
      final dir = Directory(path).absolute;
      if (roots.any((existing) => existing.path == dir.path)) return;
      roots.add(dir);
    }

    addRoot(Directory.current.path);
    addRoot(File(Platform.resolvedExecutable).parent.path);

    for (final root in roots) {
      var current = root;
      for (var depth = 0; depth < 6; depth++) {
        final candidate = File(
          '${current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}yoloit',
        );
        if (candidate.existsSync()) {
          _cached = candidate.path;
          return candidate.path;
        }
        final parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return null;
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
