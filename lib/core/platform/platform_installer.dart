import 'dart:io';

import 'package:yoloit/core/platform/macos_update_manifest.dart';

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
    if (Platform.isMacOS) return MacosPlatformInstaller();
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
  ///
  /// On macOS pass [releaseTag] (e.g. `v1.0.57`) to download the Squirrel-style
  /// ZIP from `latest-mac.yml`. [downloadUrl] is ignored on macOS.
  /// [onProgress] is called with 0.0–1.0 during download, null during setup.
  /// Throws on failure.
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
    String? releaseTag,
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
    String? releaseTag,
  }) async {
    final token = await downloadAndPrepare(
      downloadUrl: downloadUrl,
      onProgress: onProgress,
      releaseTag: releaseTag,
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
  MacosPlatformInstaller({ProcessRunner? processRunner})
      : _run = processRunner ?? Process.run;

  final ProcessRunner _run;
  String? _shipScriptPath;
  String? _stagedAppPath;

  @override
  bool get supportsInAppInstall => true;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async {
    try {
      final plistPath = '${_currentAppBundlePath()}/Contents/Info.plist';
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
    String? releaseTag,
  }) async {
    final tag = releaseTag?.trim();
    if (tag == null || tag.isEmpty) {
      throw ArgumentError('releaseTag is required for macOS zip updates');
    }

    onProgress(null, 'Reading update manifest…');
    final manifest = await MacosUpdateManifest.fetch(
      feedUrl: MacosUpdateManifest.feedUrlForTag(tag),
    );
    final file = manifest.fileForCurrentArch();
    final zipUrl = manifest.downloadUrlFor(file, tagName: tag);

    onProgress(0.0, 'Downloading…');
    final tmpDir = Directory.systemTemp.createTempSync('yoloit_update_');
    final zipFile = File('${tmpDir.path}/${file.url.split('/').last}');
    await _downloadFile(zipUrl, zipFile, onProgress, 'Downloading…');

    onProgress(null, 'Verifying…');
    final bytes = await zipFile.readAsBytes();
    if (file.size != null && bytes.length != file.size) {
      throw StateError(
        'Downloaded size mismatch (expected ${file.size}, got ${bytes.length})',
      );
    }
    verifySha512Base64(bytes, file.sha512);

    onProgress(null, 'Extracting…');
    final extractDir = Directory('${tmpDir.path}/extracted');
    await extractDir.create(recursive: true);
    final extract = await _run('ditto', ['-x', '-k', zipFile.path, extractDir.path]);
    if (extract.exitCode != 0) {
      throw Exception('Extract failed: ${extract.stderr}');
    }

    final stagedApp = _findAppBundle(extractDir);
    if (stagedApp == null) {
      throw Exception('No .app bundle found in update ZIP');
    }

    final targetApp = _resolveTargetAppPath(stagedApp.path.split('/').last);
    _stagedAppPath = stagedApp.path;
    _shipScriptPath = await _writeShipItScript(tmpDir.path);

    onProgress(null, 'Ready to install');
    return targetApp;
  }

  @override
  Future<void> launchAndExit(String launchToken) async {
    final script = _shipScriptPath;
    final stagedApp = _stagedAppPath;
    if (script == null || stagedApp == null) {
      await _run('open', [launchToken]);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      exit(0);
    }

    final logFile = '${Directory.systemTemp.path}/yoloit_relaunch.log';
    final cmd =
        '/bin/bash "$script" $pid "$stagedApp" "$launchToken" "$logFile" '
        '</dev/null >>"$logFile" 2>&1 & disown';
    await _run('/bin/bash', ['-c', cmd]);

    await Future<void>.delayed(const Duration(milliseconds: 400));
    exit(0);
  }

  String _currentAppBundlePath() {
    return Platform.resolvedExecutable.split('/Contents/').first;
  }

  String _resolveTargetAppPath(String appFileName) {
    final current = _currentAppBundlePath();
    if (current.startsWith('/Applications/')) return current;
    return '/Applications/$appFileName';
  }

  Directory? _findAppBundle(Directory root) {
    if (root.path.endsWith('.app')) return root;
    for (final entity in root.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (entity.path.endsWith('.app')) return entity;
        final nested = _findAppBundle(entity);
        if (nested != null) return nested;
      }
    }
    return null;
  }

  Future<String> _writeShipItScript(String tmpDirPath) async {
    const scriptBody = r'''#!/bin/bash
set -euo pipefail
PID="$1"
NEW_APP="$2"
TARGET_APP="$3"
LOG="$4"

i=0
while kill -0 "$PID" 2>/dev/null && [ "$i" -lt 75 ]; do
  sleep 0.2
  i=$((i + 1))
done
sleep 0.5

BACKUP="${TARGET_APP}.yoloit.old"
rm -rf "$BACKUP"
if [ -d "$TARGET_APP" ]; then
  mv "$TARGET_APP" "$BACKUP"
fi
mv "$NEW_APP" "$TARGET_APP"
rm -rf "$BACKUP"

xattr -dr com.apple.quarantine "$TARGET_APP" 2>/dev/null || true
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
if [ -x "$LSREGISTER" ]; then
  "$LSREGISTER" -f -R -trusted "$TARGET_APP" 2>/dev/null || true
fi

CLI_SOURCE="$TARGET_APP/Contents/Frameworks/App.framework/Versions/A/Resources/flutter_assets/tools/yoloit"
if [ -f "$CLI_SOURCE" ]; then
  if [ -n "${HOME:-}" ]; then
    USER_DIR="$HOME/.config/yoloit"
    mkdir -p "$USER_DIR"
    ln -sf "$CLI_SOURCE" "$USER_DIR/yoloit" 2>/dev/null || true
  fi
  mkdir -p /usr/local/bin 2>/dev/null || true
  ln -sf "$CLI_SOURCE" /usr/local/bin/yoloit 2>/dev/null || true
fi

open "$TARGET_APP" >>"$LOG" 2>&1
''';
    final scriptFile = File('$tmpDirPath/yoloit_shipit.sh');
    await scriptFile.writeAsString(scriptBody);
    await _run('chmod', ['+x', scriptFile.path]);
    return scriptFile.path;
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
    String? releaseTag,
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
    String? releaseTag,
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
