import 'dart:io';

typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments, {
  String? workingDirectory,
  Map<String, String>? environment,
  bool includeParentEnvironment,
  bool runInShell,
});

typedef ProgressCallback = void Function(double? progress, String status);

/// Platform-aware in-app installer for YoLoIT updates.
///
/// Two-phase API:
///   1. [downloadAndPrepare] — downloads & prepares the update, returns a launch token.
///   2. [launchAndExit]      — applies the prepared update and exits the current process.
///
/// This separation lets the caller show a countdown before the restart.
abstract class PlatformInstaller {
  const PlatformInstaller();

  /// Singleton — picks the right implementation based on the current OS.
  static PlatformInstaller? _instance;
  static PlatformInstaller get instance {
    _instance ??= _create();
    return _instance!;
  }

  /// Override the singleton (useful for testing).
  // ignore: use_setters_to_change_properties
  static void setInstance(PlatformInstaller instance) => _instance = instance;

  static PlatformInstaller _create() {
    if (Platform.isMacOS) return const MacosPlatformInstaller();
    if (Platform.isLinux) return const LinuxPlatformInstaller();
    if (Platform.isWindows) return const WindowsPlatformInstaller();
    return const LinuxPlatformInstaller();
  }

  /// Returns true if this platform supports in-app install (not just browser).
  bool get supportsInAppInstall;

  /// Reads the app version from the running binary's Info.plist / metadata.
  /// Falls back to [fallback] if it cannot be determined.
  Future<String> getAppVersion({String fallback = '0.0.0'});

  /// Phase 1 — download and prepare the update.
  ///
  /// Returns a *launch token* (an app path on macOS, a helper-script path on
  /// Windows/Linux) to be passed to [launchAndExit] when the caller is ready.
  /// [onProgress] is called with 0.0–1.0 during download, null during setup.
  /// Throws on failure.
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
  });

  /// Phase 2 — apply the prepared update and exit the current process.
  ///
  /// On macOS: opens the installed .app and exits.
  /// On Windows/Linux: launches the helper update script and exits;
  /// the script waits for this process to finish, copies new files, restarts.
  Future<void> launchAndExit(String launchToken);

  // ── Legacy convenience ────────────────────────────────────────────────────

  /// Downloads, prepares, and immediately applies the update (old one-shot API).
  Future<void> install({
    required String downloadUrl,
    required ProgressCallback onProgress,
  }) async {
    final token = await downloadAndPrepare(
      downloadUrl: downloadUrl,
      onProgress: onProgress,
    );
    await launchAndExit(token);
  }
}

// ── helpers ───────────────────────────────────────────────────────────────────

Future<void> _downloadFile(
  String url,
  File dest,
  ProgressCallback onProgress,
  String label,
) async {
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 15);
  try {
    final req = await client.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, 'YoLoIT/updater');
    final resp = await req.close();
    if (resp.statusCode != 200) {
      throw Exception('Download failed: HTTP ${resp.statusCode}');
    }
    final total = resp.contentLength;
    var received = 0;
    final sink = dest.openWrite();
    await for (final chunk in resp) {
      sink.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total, label);
    }
    await sink.close();
  } finally {
    client.close();
  }
}

// ── macOS ─────────────────────────────────────────────────────────────────────

class MacosPlatformInstaller extends PlatformInstaller {
  const MacosPlatformInstaller({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async {
    try {
      final executable = Platform.resolvedExecutable;
      final appBundle = executable.split('/Contents/').first;
      final plistPath = '$appBundle/Contents/Info.plist';
      final result = await _run(
        '/usr/bin/defaults',
        ['read', plistPath, 'CFBundleShortVersionString'],
      );
      if (result.exitCode == 0) {
        final v = (result.stdout as String).trim();
        if (v.isNotEmpty) return v;
      }
    } catch (_) {}
    return fallback;
  }

  @override
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
  }) async {
    // 1. Download DMG
    onProgress(0.0, 'Downloading…');
    final tmpDir = Directory.systemTemp.createTempSync('yoloit_update_');
    final dmgFile = File('${tmpDir.path}/YoLoIT.dmg');
    await _downloadFile(downloadUrl, dmgFile, onProgress, 'Downloading…');

    // 2. Mount DMG
    onProgress(null, 'Mounting…');
    final mountPoint = '${tmpDir.path}/vol';
    await Directory(mountPoint).create();
    final mount = await _run('hdiutil', [
      'attach', dmgFile.path, '-nobrowse', '-mountpoint', mountPoint,
    ]);
    if (mount.exitCode != 0) {
      throw Exception('Mount failed: ${mount.stderr}');
    }

    try {
      // 3. Find .app inside mounted volume and copy to /Applications
      onProgress(null, 'Installing…');
      final volDir = Directory(mountPoint);
      final appEntry = volDir
          .listSync()
          .whereType<Directory>()
          .firstWhere(
            (d) => d.path.endsWith('.app'),
            orElse: () => throw Exception('No .app found in DMG'),
          );

      final appName = appEntry.path.split('/').last;
      final dest = '/Applications/$appName';
      final ditto = await _run('ditto', [appEntry.path, dest]);
      if (ditto.exitCode != 0) {
        throw Exception('Install failed: ${ditto.stderr}');
      }
      return dest; // launch token = installed .app path
    } finally {
      await _run('hdiutil', ['detach', mountPoint, '-force']);
      try { tmpDir.deleteSync(recursive: true); } catch (_) {}
    }
  }

  @override
  Future<void> launchAndExit(String launchToken) async {
    await _run('open', [launchToken]);
    await Future.delayed(const Duration(milliseconds: 500));
    exit(0);
  }
}

// ── Linux ─────────────────────────────────────────────────────────────────────

class LinuxPlatformInstaller extends PlatformInstaller {
  const LinuxPlatformInstaller();

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async => fallback;

  @override
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
  }) async {
    // 1. Download tar.gz
    onProgress(0.0, 'Downloading…');
    final tmpDir = Directory.systemTemp.createTempSync('yoloit_update_');
    final tarFile = File('${tmpDir.path}/yoloit.tar.gz');
    await _downloadFile(downloadUrl, tarFile, onProgress, 'Downloading…');

    // 2. Extract
    onProgress(null, 'Extracting…');
    final extractDir = Directory('${tmpDir.path}/extracted');
    await extractDir.create();
    final tar = await Process.run(
      'tar', ['-xzf', tarFile.path, '-C', extractDir.path],
    );
    if (tar.exitCode != 0) {
      throw Exception('Extract failed: ${tar.stderr}');
    }

    // 3. Find the bundle directory (should contain the yoloit binary)
    final bundleDir = extractDir
        .listSync()
        .whereType<Directory>()
        .firstWhere(
          (d) => File('${d.path}/yoloit').existsSync(),
          orElse: () {
            // Fallback: look one level deeper
            final nested = extractDir.listSync().whereType<Directory>().toList();
            for (final d in nested) {
              final sub = d.listSync().whereType<Directory>().toList();
              for (final s in sub) {
                if (File('${s.path}/yoloit').existsSync()) return s;
              }
            }
            throw Exception('Could not find yoloit binary in extracted archive');
          },
        );

    // 4. Determine current install dir and write update script
    final currentExe = Platform.resolvedExecutable;
    final currentBundleDir = File(currentExe).parent.path;

    final scriptFile = File('${tmpDir.path}/yoloit_update.sh');
    await scriptFile.writeAsString('''#!/bin/bash
sleep 2
cp -rf "${bundleDir.path}/"* "$currentBundleDir/"
chmod +x "$currentBundleDir/yoloit"
"$currentBundleDir/yoloit" &
''');
    await Process.run('chmod', ['+x', scriptFile.path]);

    return scriptFile.path;
  }

  @override
  Future<void> launchAndExit(String launchToken) async {
    await Process.start(
      'bash', [launchToken],
      mode: ProcessStartMode.detached,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}

// ── Windows ───────────────────────────────────────────────────────────────────

class WindowsPlatformInstaller extends PlatformInstaller {
  const WindowsPlatformInstaller({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async {
    try {
      final exePath = Platform.resolvedExecutable;
      final result = await _run(
        'powershell',
        [
          '-NoProfile',
          '-Command',
          '(Get-Item "$exePath").VersionInfo.ProductVersion',
        ],
      );
      if (result.exitCode == 0) {
        final version = (result.stdout as String).trim();
        if (version.isNotEmpty && version != '0.0.0.0') return version;
      }
    } catch (_) {}
    return fallback;
  }

  @override
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
  }) async {
    // 1. Download ZIP
    onProgress(0.0, 'Downloading…');
    final tmpDir = Directory.systemTemp.createTempSync('yoloit_update_');
    final zipFile = File('${tmpDir.path}\\yoloit.zip');
    await _downloadFile(downloadUrl, zipFile, onProgress, 'Downloading…');

    // 2. Extract ZIP using PowerShell
    onProgress(null, 'Extracting…');
    final extractDir = '${tmpDir.path}\\extracted';
    final extract = await Process.run('powershell', [
      '-NoProfile', '-Command',
      'Expand-Archive -LiteralPath "${zipFile.path}" -DestinationPath "$extractDir" -Force',
    ]);
    if (extract.exitCode != 0) {
      throw Exception('Extract failed: ${extract.stderr}');
    }

    // 3. Current install dir
    final currentExe = Platform.resolvedExecutable;
    final currentDir = File(currentExe).parent.path;
    final newExe = File(currentExe).uri.pathSegments.last; // yoloit.exe

    // 4. Write update batch script
    final scriptFile = File('${tmpDir.path}\\yoloit_update.bat');
    await scriptFile.writeAsString(
      '@echo off\r\n'
      'timeout /t 2 /nobreak > nul\r\n'
      'robocopy "$extractDir" "$currentDir" /E /IS /IT /R:3 /W:1 > nul\r\n'
      'start "" "$currentDir\\$newExe"\r\n',
    );

    return scriptFile.path;
  }

  @override
  Future<void> launchAndExit(String launchToken) async {
    await Process.start(
      'cmd', ['/C', 'start', '/B', '/MIN', launchToken],
      mode: ProcessStartMode.detached,
    );
    await Future.delayed(const Duration(milliseconds: 300));
    exit(0);
  }
}
