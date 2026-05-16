import 'dart:io';

import 'package:path/path.dart' as p;

class LocalModelRegistryLocator {
  const LocalModelRegistryLocator._();

  static const _registrySegments = <String>[
    'third_party',
    'flutter_local_models',
    'registry',
    'models',
  ];

  static Directory resolve({
    String? currentDirectory,
    String? executablePath,
    Map<String, String>? environment,
  }) {
    final checked = <String>[];
    for (final root in _candidateRoots(
      currentDirectory: currentDirectory,
      executablePath: executablePath,
      environment: environment,
    )) {
      final directory = Directory(
        p.joinAll(<String>[root, ..._registrySegments]),
      );
      checked.add(directory.path);
      if (directory.existsSync()) {
        return directory;
      }
    }

    throw StateError(
      'Cannot find flutter_local_models registry at '
      'third_party/flutter_local_models/registry/models. Checked: '
      '${checked.join(', ')}',
    );
  }

  static Future<Directory> resolveAsync({
    String? currentDirectory,
    String? executablePath,
    Map<String, String>? environment,
    Uri? packageConfig,
  }) async {
    final checked = <String>[];
    for (final root in _candidateRoots(
      currentDirectory: currentDirectory,
      executablePath: executablePath,
      environment: environment,
      packageConfig: packageConfig,
    )) {
      final directory = Directory(
        p.joinAll(<String>[root, ..._registrySegments]),
      );
      checked.add(directory.path);
      if (directory.existsSync()) {
        return directory;
      }
    }

    throw StateError(
      'Cannot find flutter_local_models registry at '
      'third_party/flutter_local_models/registry/models. Checked: '
      '${checked.join(', ')}',
    );
  }

  static Iterable<String> _candidateRoots({
    String? currentDirectory,
    String? executablePath,
    Map<String, String>? environment,
    Uri? packageConfig,
  }) sync* {
    final seen = <String>{};

    Iterable<String> walkUp(String startPath) sync* {
      var current = _normalize(startPath);
      for (var depth = 0; depth < 16; depth += 1) {
        if (seen.add(current)) yield current;

        final nestedCheckout = p.join(current, 'yoloit');
        if (seen.add(nestedCheckout)) yield nestedCheckout;

        final parent = p.dirname(current);
        if (parent == current) break;
        current = parent;
      }
    }

    Iterable<String> addDirectory(String? value) sync* {
      if (value == null || value.trim().isEmpty) return;
      yield* walkUp(value.trim());
    }

    final env = environment ?? Platform.environment;
    yield* addDirectory(currentDirectory ?? Directory.current.path);
    yield* addDirectory(env['PWD']);
    yield* addDirectory(env['YOLOIT_PROJECT_ROOT']);
    yield* addDirectory(env['PROJECT_DIR']);
    yield* addDirectory(_projectRootFromPackageConfig(packageConfig));

    final executable = executablePath ?? Platform.resolvedExecutable;
    if (executable.trim().isNotEmpty) {
      yield* addDirectory(p.dirname(executable.trim()));
    }
  }

  static String _normalize(String path) => p.normalize(p.absolute(path));

  static String? _projectRootFromPackageConfig(Uri? packageConfig) {
    if (packageConfig == null || !packageConfig.isScheme('file')) return null;
    final file = File.fromUri(packageConfig);
    if (p.basename(file.parent.path) != '.dart_tool') return null;
    return file.parent.parent.path;
  }
}
