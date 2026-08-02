import 'dart:io';

import 'package:path/path.dart' as p;

/// Walks upward from well-known roots (current directory, PWD,
/// YOLOIT_PROJECT_ROOT, PROJECT_DIR, and the executable's directory) looking
/// for the yoloit CLI script at `tools/yoloit` or `yoloit/tools/yoloit`.
/// Returns the script path when found, or null. When [checked] is provided,
/// every probed candidate path is added to it for error reporting.
String? findYoloitCliScript({List<String>? checked}) {
  final roots = <String?>[
    Directory.current.path,
    Platform.environment['PWD'],
    Platform.environment['YOLOIT_PROJECT_ROOT'],
    Platform.environment['PROJECT_DIR'],
    p.dirname(Platform.resolvedExecutable),
  ];
  final seen = <String>{};
  for (final root in roots) {
    if (root == null || root.trim().isEmpty) continue;
    var dir = Directory(p.normalize(p.absolute(root.trim())));
    for (var i = 0; i < 16; i++) {
      final candidates = <File>[
        File(p.join(dir.path, 'tools', 'yoloit')),
        File(p.join(dir.path, 'yoloit', 'tools', 'yoloit')),
      ];
      for (final candidate in candidates) {
        if (!seen.add(candidate.path)) continue;
        checked?.add(candidate.path);
        if (candidate.existsSync()) {
          return candidate.path;
        }
      }
      final parent = dir.parent;
      if (parent.path == dir.path) break;
      dir = parent;
    }
  }
  return null;
}
