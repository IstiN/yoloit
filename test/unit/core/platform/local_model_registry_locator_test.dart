import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/local_model_registry_locator.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync(
      'yoloit_registry_locator_test_',
    );
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('resolves registry from project root', () {
    final registry = _createRegistry(tempDir.path);

    final resolved = LocalModelRegistryLocator.resolve(
      currentDirectory: tempDir.path,
      executablePath: '',
      environment: const {},
    );

    expect(resolved.path, registry.path);
  });

  test(
    'resolves registry from parent workspace containing yoloit checkout',
    () {
      final projectRoot = Directory(p.join(tempDir.path, 'yoloit'))
        ..createSync(recursive: true);
      final registry = _createRegistry(projectRoot.path);

      final resolved = LocalModelRegistryLocator.resolve(
        currentDirectory: tempDir.path,
        executablePath: '',
        environment: const {},
      );

      expect(resolved.path, registry.path);
    },
  );

  test('walks from macOS app executable back to project root', () {
    final registry = _createRegistry(tempDir.path);
    final executablePath = p.join(
      tempDir.path,
      'build',
      'macos',
      'Build',
      'Products',
      'Debug',
      'YoLoIT (dev).app',
      'Contents',
      'MacOS',
      'YoLoIT (dev)',
    );

    final resolved = LocalModelRegistryLocator.resolve(
      currentDirectory: p.dirname(executablePath),
      executablePath: executablePath,
      environment: const {},
    );

    expect(resolved.path, registry.path);
  });

  test('resolves registry from Flutter package config in debug runs', () async {
    final registry = _createRegistry(tempDir.path);
    final packageConfig = File(
      p.join(tempDir.path, '.dart_tool', 'package_config.json'),
    )..createSync(recursive: true);

    final resolved = await LocalModelRegistryLocator.resolveAsync(
      currentDirectory: '/tmp',
      executablePath: '',
      environment: const {},
      packageConfig: packageConfig.uri,
    );

    expect(resolved.path, registry.path);
  });
}

Directory _createRegistry(String projectRoot) {
  final registry = Directory(
    p.join(
      projectRoot,
      'third_party',
      'flutter_local_models',
      'registry',
      'models',
    ),
  )..createSync(recursive: true);
  return registry;
}
