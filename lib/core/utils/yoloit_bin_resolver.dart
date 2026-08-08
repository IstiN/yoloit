import 'dart:io';

import 'package:meta/meta.dart';

/// Resolves the path to the `yoloit` CLI binary.
///
/// Checks the installed location (`~/.config/yoloit/yoloit`) first, then
/// searches up the directory tree from [alsoSearchFrom], the current working
/// directory, and the resolved executable path.
String? resolveYoloitBin({
  String? alsoSearchFrom,
  int maxDepth = 6,
}) {
  final home = Platform.environment['HOME'] ?? '';
  if (home.isNotEmpty) {
    final installed = File('$home/.config/yoloit/yoloit');
    if (installed.existsSync()) return installed.path;
  }

  final roots = <Directory>[
    Directory.current,
    File(Platform.resolvedExecutable).parent,
    if (alsoSearchFrom != null) Directory(alsoSearchFrom),
  ];
  return searchUpTreeForYoloitBin(roots, maxDepth: maxDepth);
}

/// Walks each root (deduplicated, empty paths skipped) and its ancestors —
/// at most [maxDepth] levels — looking for a `tools/yoloit` executable.
/// Extracted from [resolveYoloitBin] so tests can drive the walk with
/// temporary-directory fixtures independent of the process environment.
@visibleForTesting
String? searchUpTreeForYoloitBin(List<Directory> roots, {int maxDepth = 6}) {
  final unique = <Directory>[];
  for (final root in roots) {
    if (root.path.isEmpty) continue;
    final dir = root.absolute;
    if (unique.any((existing) => existing.path == dir.path)) continue;
    unique.add(dir);
  }

  for (final root in unique) {
    var current = root;
    for (var depth = 0; depth < maxDepth; depth++) {
      final candidate = File(
        '${current.path}${Platform.pathSeparator}tools${Platform.pathSeparator}yoloit',
      );
      if (candidate.existsSync()) return candidate.path;
      final parent = current.parent;
      if (parent.path == current.path) break;
      current = parent;
    }
  }
  return null;
}
