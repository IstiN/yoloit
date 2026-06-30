import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/updates/data/update_service.dart';

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
}
