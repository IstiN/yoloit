import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/platform/platform_installer.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/updates/data/update_check_result.dart';

export 'package:yoloit/features/updates/data/update_check_result.dart';

// ── UpdateInfo ────────────────────────────────────────────────────────────────

class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.tagName,
    required this.releaseUrl,
    required this.releaseNotes,
    this.downloadUrl,
  });

  /// Clean version string, e.g. "0.0.2"
  final String version;

  /// Tag as published on GitHub, e.g. "v0.0.2"
  final String tagName;

  /// HTML release page URL.
  final String releaseUrl;

  /// Markdown release notes body.
  final String releaseNotes;

  /// Direct DMG/asset download URL (first .dmg asset, if present).
  final String? downloadUrl;
}

// ── UpdateService ─────────────────────────────────────────────────────────────

class UpdateService {
  const UpdateService._();

  static const _owner = 'IstiN';
  static const _repo = 'yoloit';

  /// Current app version — read from Info.plist at runtime.
  /// Falls back to pubspec version if plist read fails.
  static String? _cachedVersion;
  static const _fallbackVersion = '0.0.0';

  static Future<String> getAppVersion() async {
    if (_cachedVersion != null) return _cachedVersion!;
    _cachedVersion = await PlatformInstaller.instance
        .getAppVersion(fallback: _fallbackVersion);
    return _cachedVersion!;
  }

  /// Synchronous getter for cached version (after first async call).
  static String get currentVersion => _cachedVersion ?? _fallbackVersion;

  static const _apiUrl =
      'https://api.github.com/repos/$_owner/$_repo/releases/latest';

  /// True when running in debug/profile mode (flutter run, DevTools, IDE).
  /// Release builds produced by `flutter build macos --release` return false.
  static bool get isDevBuild => kDebugMode || kProfileMode;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Checks GitHub for a newer release.
  /// Also updates the last-check timestamp in prefs on success.
  ///
  /// Pass [force] = true to skip the dev-build guard (e.g. "Check Now" button).
  static Future<UpdateCheckResult> checkForUpdate({bool force = false}) async {
    // Never auto-check in dev builds — only allow manual force-check
    if (!force && isDevBuild) return UpdateCheckResult.upToDate();

    try {
      final appVersion = await getAppVersion();
      final info = await _fetchLatestRelease();
      if (info == null) {
        return UpdateCheckResult.failed(
          'Could not reach GitHub releases API. '
          'If you hit rate limits, set GITHUB_TOKEN in your environment.',
        );
      }

      await SessionPrefs.saveLastUpdateCheckMs(
        DateTime.now().millisecondsSinceEpoch,
      );

      final skipped = await SessionPrefs.getSkippedVersion();
      if (skipped == info.version) {
        return UpdateCheckResult.skipped(info.version);
      }

      return isVersionNewer(info.version, appVersion)
          ? UpdateCheckResult.available(info)
          : UpdateCheckResult.upToDate();
    } on SocketException {
      return UpdateCheckResult.failed('No network connection.');
    } catch (e) {
      return UpdateCheckResult.failed('Update check failed: $e');
    }
  }

  /// Opens the release page in the system browser (fallback).
  static Future<void> openRelease(UpdateInfo info) async {
    await PlatformLauncher.instance.openUrl(info.releaseUrl);
  }

  static Future<bool> _ensureInAppInstall(UpdateInfo info) async {
    final installer = PlatformInstaller.instance;
    if (!installer.supportsInAppInstall) {
      await openRelease(info);
      return false;
    }
    if (Platform.isMacOS) return true;
    if (info.downloadUrl == null) {
      await openRelease(info);
      return false;
    }
    return true;
  }

  /// Downloads the update and prepares it for installation (phase 1).
  /// Returns a launch token to be passed to [applyUpdate].
  /// Falls back to [openRelease] if in-app install is not supported.
  static Future<String?> downloadAndPrepare(
    UpdateInfo info, {
    required void Function(double? progress, String status) onProgress,
  }) async {
    if (!await _ensureInAppInstall(info)) return null;
    return PlatformInstaller.instance.downloadAndPrepare(
      downloadUrl: info.downloadUrl ?? '',
      releaseTag: info.tagName,
      onProgress: onProgress,
    );
  }

  /// Applies a prepared update (phase 2) — exits the process.
  static Future<void> applyUpdate(String launchToken) =>
      PlatformInstaller.instance.launchAndExit(launchToken);

  /// Downloads the DMG, mounts it, copies the app to /Applications, relaunches.
  /// [onProgress] receives values 0.0–1.0 during download, then null during install steps.
  /// Throws on failure.
  static Future<void> downloadAndInstall(
    UpdateInfo info, {
    required void Function(double? progress, String status) onProgress,
  }) async {
    if (!await _ensureInAppInstall(info)) return;
    await PlatformInstaller.instance.install(
      downloadUrl: info.downloadUrl ?? '',
      releaseTag: info.tagName,
      onProgress: onProgress,
    );
  }

  /// Skips this version (don't nag again until a newer one is found).
  static Future<void> skipVersion(String version) =>
      SessionPrefs.saveSkippedVersion(version);

  // ── Helpers ────────────────────────────────────────────────────────────────

  static Future<UpdateInfo?> _fetchLatestRelease() async {
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 8);
    try {
      final req = await client.getUrl(Uri.parse(_apiUrl));
      req.headers
        ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json')
        ..set(HttpHeaders.userAgentHeader, 'YoLoIT/$currentVersion');
      final token = Platform.environment['GITHUB_TOKEN'];
      if (token != null && token.isNotEmpty) {
        req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      }

      final resp = await req.close().timeout(const Duration(seconds: 10));
      if (resp.statusCode != 200) {
        if (resp.statusCode == 403) {
          throw StateError(
            'GitHub API rate limit exceeded. Set GITHUB_TOKEN to raise limits.',
          );
        }
        return null;
      }

      final body = await resp.transform(utf8.decoder).join();
      final json = jsonDecode(body) as Map<String, dynamic>;
      return parseGitHubReleaseJson(
        json,
        isMacOS: Platform.isMacOS,
        isWindows: Platform.isWindows,
        isLinux: Platform.isLinux,
        macosAssetName: Platform.isMacOS ? expectedMacosAssetName(versionFromTag(json)) : null,
      );
    } finally {
      client.close();
    }
  }

  @visibleForTesting
  static String versionFromTag(Map<String, dynamic> json) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    return tagName.startsWith('v') ? tagName.substring(1) : tagName;
  }

  @visibleForTesting
  static UpdateInfo? parseGitHubReleaseJson(
    Map<String, dynamic> json, {
    required bool isMacOS,
    required bool isWindows,
    required bool isLinux,
    String? macosAssetName,
  }) {
    final tagName = (json['tag_name'] as String? ?? '').trim();
    if (tagName.isEmpty) return null;
    final version = versionFromTag(json);
    final htmlUrl = json['html_url'] as String? ?? '';
    final notes = json['body'] as String? ?? '';

    final assets = json['assets'] as List<dynamic>? ?? [];
    String? downloadUrl;
    String? fallbackUrl;
    for (final a in assets) {
      final asset = a as Map<String, dynamic>;
      final name = (asset['name'] as String? ?? '').toLowerCase();
      final url = asset['browser_download_url'] as String?;
      if (isMacOS && name.endsWith('.dmg')) {
        fallbackUrl ??= url;
        if (macosAssetName != null && name == macosAssetName.toLowerCase()) {
          downloadUrl = url;
          break;
        }
      } else if (isWindows && name.endsWith('.zip')) {
        downloadUrl = url;
        break;
      } else if (isLinux && name.endsWith('.tar.gz')) {
        downloadUrl = url;
        break;
      }
    }
    downloadUrl ??= fallbackUrl;

    return UpdateInfo(
      version: version,
      tagName: tagName,
      releaseUrl: htmlUrl,
      releaseNotes: notes,
      downloadUrl: downloadUrl,
    );
  }

  /// Returns the expected macOS DMG asset name for the current CPU architecture,
  /// or `null` if the architecture cannot be determined.
  @visibleForTesting
  static String? expectedMacosAssetName(String version) {
    final abi = Abi.current();
    if (abi == Abi.macosArm64) {
      return 'yoloit-macos-arm64-$version.dmg';
    }
    if (abi == Abi.macosX64) {
      return 'yoloit-macos-x86_64-$version.dmg';
    }
    return null;
  }

  /// Returns true when [candidate] is strictly newer than [current].
  /// Compares semver segments numerically (major.minor.patch).
  @visibleForTesting
  static bool isVersionNewer(String candidate, String current) {
    List<int> parse(String v) => v
        .split('.')
        .map((s) => int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();

    final c = parse(candidate);
    final b = parse(current);
    final len = c.length > b.length ? c.length : b.length;
    for (var i = 0; i < len; i++) {
      final cv = i < c.length ? c[i] : 0;
      final bv = i < b.length ? b[i] : 0;
      if (cv > bv) return true;
      if (cv < bv) return false;
    }
    return false;
  }
}
