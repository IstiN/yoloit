import 'dart:io';

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

  final roots = <Directory>[];
  void addRoot(String path) {
    if (path.isEmpty) return;
    final dir = Directory(path).absolute;
    if (roots.any((existing) => existing.path == dir.path)) return;
    roots.add(dir);
  }

  addRoot(Directory.current.path);
  addRoot(File(Platform.resolvedExecutable).parent.path);
  if (alsoSearchFrom != null) addRoot(alsoSearchFrom);

  for (final root in roots) {
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
