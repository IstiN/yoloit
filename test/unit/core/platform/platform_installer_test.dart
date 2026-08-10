import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_installer.dart';

import '../../../helpers/fake_http_overrides.dart';
import '../../../helpers/fake_process_runner.dart';

void main() {
  tearDown(() {
    PlatformInstaller.setInstance(MacosPlatformInstaller());
  });

  group('MacosPlatformInstaller', () {
    late FakeProcessRunner fakeRunner;
    late MacosPlatformInstaller installer;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      installer = MacosPlatformInstaller(processRunner: fakeRunner.run);
    });

    test('supportsInAppInstall is true', () {
      expect(installer.supportsInAppInstall, isTrue);
    });

    test('getAppVersion returns fallback when defaults read fails', () async {
      fakeRunner.mockResult('/usr/bin/defaults', exitCode: 1, stdout: '');
      final version = await installer.getAppVersion(fallback: '1.2.3');
      expect(version, '1.2.3');
    });

    test('getAppVersion returns trimmed version string on success', () async {
      fakeRunner.mockResult(
        '/usr/bin/defaults',
        exitCode: 0,
        stdout: '0.0.15\n',
      );
      final version = await installer.getAppVersion(fallback: '0.0.0');
      expect(version, '0.0.15');
    });

    test('getAppVersion returns fallback when stdout is empty', () async {
      fakeRunner.mockResult('/usr/bin/defaults', exitCode: 0, stdout: '   ');
      final version = await installer.getAppVersion(fallback: '0.0.0');
      expect(version, '0.0.0');
    });
  });

  group('LinuxPlatformInstaller', () {
    const installer = LinuxPlatformInstaller();

    test('supportsInAppInstall is true', () {
      expect(installer.supportsInAppInstall, isTrue);
    });

    test('getAppVersion returns fallback', () async {
      final version = await installer.getAppVersion(fallback: '9.9.9');
      expect(version, '9.9.9');
    });
  });

  group('WindowsPlatformInstaller', () {
    late FakeProcessRunner fakeRunner;
    late WindowsPlatformInstaller installer;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      installer = WindowsPlatformInstaller(processRunner: fakeRunner.run);
    });

    test('supportsInAppInstall is true', () {
      expect(installer.supportsInAppInstall, isTrue);
    });

    test('getAppVersion returns fallback when powershell fails', () async {
      fakeRunner.mockResult('powershell', exitCode: 1, stdout: '');
      final version = await installer.getAppVersion(fallback: '2.0.0');
      expect(version, '2.0.0');
    });

    test('getAppVersion returns version string from powershell', () async {
      fakeRunner.mockResult('powershell', exitCode: 0, stdout: '1.2.3\r\n');
      final version = await installer.getAppVersion(fallback: '0.0.0');
      expect(version, '1.2.3');
    });

    test('getAppVersion returns fallback when stdout is 0.0.0.0', () async {
      fakeRunner.mockResult('powershell', exitCode: 0, stdout: '0.0.0.0');
      final version = await installer.getAppVersion(fallback: '2.0.0');
      expect(version, '2.0.0');
    });
  });

  group('PlatformInstaller.instance', () {
    test('can be overridden for testing', () {
      const fake = LinuxPlatformInstaller();
      PlatformInstaller.setInstance(fake);
      expect(PlatformInstaller.instance, same(fake));
    });
  });

  group('MacosPlatformInstaller.downloadAndPrepare', () {
    final zipBytes = utf8.encode('fake zip payload for installer tests');
    late String zipSha;
    late FakeHttpOverrides httpOverrides;

    setUp(() {
      zipSha = base64.encode(sha512.convert(zipBytes).bytes);
      httpOverrides = FakeHttpOverrides();
      HttpOverrides.global = httpOverrides;
    });

    tearDown(() {
      HttpOverrides.global = null;
      _cleanupUpdateTempDirs();
    });

    void serveManifestAndZip({String? sha, int? size, int zipStatus = 200}) {
      httpOverrides.responder = (uri, headers) {
        if (uri.path.endsWith('latest-mac.yml')) {
          return FakeHttpResponse(
            200,
            utf8.encode('''
version: 1.2.3
files:
  - url: yoloit-macos-arm64-1.2.3-mac.zip
    sha512: ${sha ?? zipSha}
    size: ${size ?? zipBytes.length}
    arch: arm64
'''),
          );
        }
        return FakeHttpResponse(zipStatus, zipBytes, chunkSize: 5);
      };
    }

    test('downloads, verifies, extracts and stages the update', () async {
      serveManifestAndZip();
      final runner = _ExtractRunner()
        ..onExtract = (dir) =>
            Directory('$dir/YoLoIT.app/Contents').createSync(recursive: true);
      final installer = MacosPlatformInstaller(processRunner: runner.run);

      final progress = <double?>[];
      final statuses = <String>[];
      final token = await installer.downloadAndPrepare(
        downloadUrl: 'ignored-on-macos',
        releaseTag: 'v1.2.3',
        onProgress: (p, s) {
          progress.add(p);
          statuses.add(s);
        },
      );

      expect(token, '/Applications/YoLoIT.app');
      expect(
        statuses,
        containsAll(<String>[
          'Reading update manifest…',
          'Downloading…',
          'Verifying…',
          'Extracting…',
          'Ready to install',
        ]),
      );
      expect(progress, contains(0.0));
      expect(progress.whereType<double>(), contains(1.0));
      expect(runner.calls.any((c) => c.startsWith('ditto ')), isTrue);
      expect(runner.calls.any((c) => c.startsWith('chmod ')), isTrue);
    });

    test('requires a non-empty release tag', () async {
      serveManifestAndZip();
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          onProgress: (_, _) {},
        ),
        throwsArgumentError,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: '  ',
          onProgress: (_, _) {},
        ),
        throwsArgumentError,
      );
    });

    test('finds a nested .app bundle inside the archive', () async {
      serveManifestAndZip();
      final runner = _ExtractRunner()
        ..onExtract = (dir) =>
            Directory('$dir/wrapper/Nested.app').createSync(recursive: true);
      final installer = MacosPlatformInstaller(processRunner: runner.run);
      final token = await installer.downloadAndPrepare(
        downloadUrl: 'x',
        releaseTag: 'v1.2.3',
        onProgress: (_, _) {},
      );
      expect(token, '/Applications/Nested.app');
    });

    test('throws when the archive has no .app bundle', () async {
      serveManifestAndZip();
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsA(
          predicate((e) => e.toString().contains('No .app bundle found')),
        ),
      );
    });

    test('throws when the manifest cannot be fetched', () async {
      httpOverrides.responder =
          (uri, headers) => const FakeHttpResponse(404, <int>[]);
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsA(isA<HttpException>()),
      );
    });

    test('throws when the zip download fails', () async {
      serveManifestAndZip(zipStatus: 500);
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsA(
          predicate((e) => e.toString().contains('Download failed: HTTP 500')),
        ),
      );
    });

    test('throws on a download size mismatch', () async {
      serveManifestAndZip(size: zipBytes.length + 3);
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsA(predicate((e) => e.toString().contains('size mismatch'))),
      );
    });

    test('throws on a sha512 mismatch', () async {
      serveManifestAndZip(sha: 'bogus==');
      final installer = MacosPlatformInstaller(
        processRunner: _ExtractRunner().run,
      );
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsStateError,
      );
    });

    test('throws when extraction fails', () async {
      serveManifestAndZip();
      final runner = _ExtractRunner()..dittoExitCode = 1;
      final installer = MacosPlatformInstaller(processRunner: runner.run);
      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'x',
          releaseTag: 'v1.2.3',
          onProgress: (_, _) {},
        ),
        throwsA(predicate((e) => e.toString().contains('Extract failed'))),
      );
    });
  });

  group('LinuxPlatformInstaller.downloadAndPrepare', () {
    const installer = LinuxPlatformInstaller();
    late Directory workDir;
    late FakeHttpOverrides httpOverrides;

    setUp(() {
      workDir = Directory.systemTemp.createTempSync('linux_installer_test_');
      httpOverrides = FakeHttpOverrides();
      HttpOverrides.global = httpOverrides;
    });

    tearDown(() {
      HttpOverrides.global = null;
      if (workDir.existsSync()) workDir.deleteSync(recursive: true);
      _cleanupUpdateTempDirs();
    });

    /// Builds a real tar.gz from the directories created by [populate].
    Future<List<int>> buildTarGz(
      String name,
      void Function(Directory root) populate,
    ) async {
      final src = Directory('${workDir.path}/$name')
        ..createSync(recursive: true);
      populate(src);
      final entries = src
          .listSync()
          .map((e) => e.path.split('/').last)
          .toList();
      final tarPath = '${workDir.path}/$name.tar.gz';
      final result = await Process.run(
        'tar',
        ['-czf', tarPath, '-C', src.path, ...entries],
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return File(tarPath).readAsBytesSync();
    }

    test('downloads, extracts and writes the update script', () async {
      final bytes = await buildTarGz('ok', (root) {
        final bundle = Directory('${root.path}/bundle')..createSync();
        File('${bundle.path}/yoloit').writeAsStringSync('#!/bin/sh\n');
      });
      httpOverrides.responder =
          (uri, headers) => FakeHttpResponse(200, bytes);

      final statuses = <String>[];
      final scriptPath = await installer.downloadAndPrepare(
        downloadUrl: 'https://example.test/yoloit.tar.gz',
        onProgress: (p, s) => statuses.add(s),
      );

      final script = File(scriptPath);
      expect(script.existsSync(), isTrue);
      final content = script.readAsStringSync();
      expect(content, contains('cp -rf'));
      expect(
        content,
        contains(File(Platform.resolvedExecutable).parent.path),
      );
      expect(statuses, containsAll(<String>['Downloading…', 'Extracting…']));
    });

    test('finds the bundle one level deeper in the archive', () async {
      final bytes = await buildTarGz('nested', (root) {
        final inner = Directory('${root.path}/outer/inner')
          ..createSync(recursive: true);
        File('${inner.path}/yoloit').writeAsStringSync('#!/bin/sh\n');
      });
      httpOverrides.responder =
          (uri, headers) => FakeHttpResponse(200, bytes);

      final scriptPath = await installer.downloadAndPrepare(
        downloadUrl: 'https://example.test/yoloit.tar.gz',
        onProgress: (_, _) {},
      );
      expect(
        File(scriptPath).readAsStringSync(),
        contains('inner'),
      );
    });

    test('throws when the archive has no yoloit binary', () async {
      final bytes = await buildTarGz('nobin', (root) {
        final bundle = Directory('${root.path}/bundle')..createSync();
        File('${bundle.path}/README').writeAsStringSync('nope');
      });
      httpOverrides.responder =
          (uri, headers) => FakeHttpResponse(200, bytes);

      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'https://example.test/yoloit.tar.gz',
          onProgress: (_, _) {},
        ),
        throwsA(
          predicate(
            (e) => e.toString().contains('Could not find yoloit binary'),
          ),
        ),
      );
    });

    test('throws when the archive cannot be extracted', () async {
      httpOverrides.responder = (uri, headers) =>
          FakeHttpResponse(200, utf8.encode('not a gzip archive'));

      expect(
        installer.downloadAndPrepare(
          downloadUrl: 'https://example.test/yoloit.tar.gz',
          onProgress: (_, _) {},
        ),
        throwsA(predicate((e) => e.toString().contains('Extract failed'))),
      );
    });
  });
}

/// Deletes `yoloit_update_*` staging dirs created by downloadAndPrepare.
void _cleanupUpdateTempDirs() {
  for (final entity in Directory.systemTemp.listSync()) {
    if (entity is Directory && entity.path.contains('yoloit_update_')) {
      try {
        entity.deleteSync(recursive: true);
      } catch (_) {}
    }
  }
}

/// [ProcessRunner] that records calls and optionally materializes an
/// extraction result when `ditto` is invoked (mimicking a real unzip).
class _ExtractRunner {
  final List<String> calls = <String>[];
  int dittoExitCode = 0;
  void Function(String extractDir)? onExtract;

  Future<ProcessResult> run(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
  }) async {
    calls.add('$executable ${arguments.join(' ')}');
    if (executable == 'ditto') {
      onExtract?.call(arguments[3]);
      return ProcessResult(0, dittoExitCode, '', 'ditto error');
    }
    return ProcessResult(0, 0, '', '');
  }
}
