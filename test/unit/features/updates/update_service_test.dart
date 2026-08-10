import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_installer.dart';
import 'package:yoloit/core/session/session_prefs.dart';
import 'package:yoloit/features/updates/data/update_service.dart';

import '../../../helpers/fake_http_overrides.dart';

void main() {
  group('UpdateService.isVersionNewer', () {
    test('detects newer patch', () {
      expect(UpdateService.isVersionNewer('1.0.235', '1.0.234'), isTrue);
    });

    test('detects newer minor', () {
      expect(UpdateService.isVersionNewer('1.1.0', '1.0.999'), isTrue);
    });

    test('rejects same version', () {
      expect(UpdateService.isVersionNewer('1.0.235', '1.0.235'), isFalse);
    });

    test('rejects older version', () {
      expect(UpdateService.isVersionNewer('1.0.56', '1.0.235'), isFalse);
    });
  });

  group('UpdateService.parseGitHubReleaseJson', () {
    const releaseJson = {
      'tag_name': 'v1.0.235',
      'html_url': 'https://github.com/IstiN/yoloit/releases/tag/v1.0.235',
      'body': 'Release notes',
      'assets': [
        {
          'name': 'yoloit-macos-arm64-1.0.235.dmg',
          'browser_download_url':
              'https://github.com/IstiN/yoloit/releases/download/v1.0.235/yoloit-macos-arm64-1.0.235.dmg',
        },
        {
          'name': 'yoloit-macos-x86_64-1.0.235.dmg',
          'browser_download_url':
              'https://github.com/IstiN/yoloit/releases/download/v1.0.235/yoloit-macos-x86_64-1.0.235.dmg',
        },
      ],
    };

    test('picks architecture-specific macOS dmg', () {
      final info = UpdateService.parseGitHubReleaseJson(
        releaseJson,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        macosAssetName: 'yoloit-macos-arm64-1.0.235.dmg',
      );
      expect(info, isNotNull);
      expect(info!.version, '1.0.235');
      expect(info.tagName, 'v1.0.235');
      expect(
        info.downloadUrl,
        endsWith('yoloit-macos-arm64-1.0.235.dmg'),
      );
    });

    test('falls back to first dmg when arch asset missing', () {
      final info = UpdateService.parseGitHubReleaseJson(
        releaseJson,
        isMacOS: true,
        isWindows: false,
        isLinux: false,
        macosAssetName: 'yoloit-macos-unknown-1.0.235.dmg',
      );
      expect(info?.downloadUrl, endsWith('.dmg'));
    });

    test('selects windows zip asset', () {
      final info = UpdateService.parseGitHubReleaseJson(
        {
          ...releaseJson,
          'assets': [
            {
              'name': 'yoloit-windows-x64-1.0.235.zip',
              'browser_download_url':
                  'https://github.com/IstiN/yoloit/releases/download/v1.0.235/yoloit-windows-x64-1.0.235.zip',
            },
          ],
        },
        isMacOS: false,
        isWindows: true,
        isLinux: false,
      );
      expect(info?.downloadUrl, endsWith('.zip'));
    });
  });

  group('UpdateService.expectedMacosAssetName', () {
    test('returns arm64 dmg name', () {
      expect(
        UpdateService.expectedMacosAssetName('1.0.235'),
        anyOf(
          'yoloit-macos-arm64-1.0.235.dmg',
          'yoloit-macos-x86_64-1.0.235.dmg',
        ),
      );
    });
  });

  group('UpdateService.checkForUpdate', () {
    late FakeHttpOverrides httpOverrides;

    setUpAll(() {
      TestWidgetsFlutterBinding.ensureInitialized();
      // Pin the "current" app version; the first check caches it statically.
      PlatformInstaller.setInstance(_FakeInstaller());
    });

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      httpOverrides = FakeHttpOverrides(
        responder: (uri, headers) =>
            githubReleaseResponse(200, tagName: 'v9.9.9'),
      );
      HttpOverrides.global = httpOverrides;
    });

    tearDown(() {
      HttpOverrides.global = null;
    });

    test('dev builds never auto-check unless forced', () async {
      final result = await UpdateService.checkForUpdate();
      expect(result.status, UpdateCheckStatus.upToDate);
      expect(httpOverrides.requestCount, 0);
    });

    test('reports an available update for a newer release', () async {
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.available);
      expect(result.info?.version, '9.9.9');
      expect(result.info?.tagName, 'v9.9.9');
      // The successful check stamps the last-check timestamp.
      expect(await SessionPrefs.getLastUpdateCheckMs(), isNotNull);
    });

    test('sends accept and user-agent headers', () async {
      Map<String, List<String>>? seen;
      httpOverrides.responder = (uri, headers) {
        seen = headers.values;
        return githubReleaseResponse(200, tagName: 'v9.9.9');
      };
      await UpdateService.checkForUpdate(force: true);
      expect(seen, isNotNull);
      expect(
        seen![HttpHeaders.acceptHeader]?.single,
        'application/vnd.github+json',
      );
      expect(
        seen![HttpHeaders.userAgentHeader]?.single,
        startsWith('YoLoIT/'),
      );
    });

    test('reports up-to-date for an older or equal release', () async {
      httpOverrides.responder =
          (uri, headers) => githubReleaseResponse(200, tagName: 'v1.0.0');
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.upToDate);
    });

    test('reports skipped when the version was skipped by the user', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'updates.skippedVersion': '9.9.9',
      });
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.skipped);
      expect(result.skippedVersion, '9.9.9');
    });

    test('fails gracefully on a non-200 response', () async {
      httpOverrides.responder =
          (uri, headers) => const FakeHttpResponse(500, <int>[]);
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.failed);
      expect(
        result.errorMessage,
        contains('Could not reach GitHub releases API'),
      );
    });

    test('fails with the rate-limit message on HTTP 403', () async {
      httpOverrides.responder =
          (uri, headers) => const FakeHttpResponse(403, <int>[]);
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, contains('rate limit'));
    });

    test('fails with a network message on SocketException', () async {
      httpOverrides.responder =
          (uri, headers) => throw const SocketException('offline');
      final result = await UpdateService.checkForUpdate(force: true);
      expect(result.status, UpdateCheckStatus.failed);
      expect(result.errorMessage, 'No network connection.');
    });
  });
}

// ── Fakes ────────────────────────────────────────────────────────────────────

class _FakeInstaller extends PlatformInstaller {
  @override
  bool get supportsInAppInstall => false;

  @override
  Future<String> getAppVersion({String fallback = '0.0.0'}) async => '1.0.0';

  @override
  Future<String> downloadAndPrepare({
    required String downloadUrl,
    required ProgressCallback onProgress,
    String? releaseTag,
  }) async =>
      'token';

  @override
  Future<void> launchAndExit(String launchToken) async {}
}
