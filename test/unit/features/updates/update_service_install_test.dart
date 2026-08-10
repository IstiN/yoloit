import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_installer.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';
import 'package:yoloit/features/updates/data/update_service.dart';

import '../../../helpers/fake_platform_installer.dart';

void main() {
  group('UpdateService install flow (_ensureInAppInstall)', () {
    late FakePlatformInstaller installer;
    late _RecordingLauncher launcher;

    const info = UpdateInfo(
      version: '2.0.0',
      tagName: 'v2.0.0',
      releaseUrl: 'https://example.test/release/v2.0.0',
      releaseNotes: 'notes',
      downloadUrl: 'https://example.test/app.zip',
    );

    setUp(() {
      installer = FakePlatformInstaller();
      launcher = _RecordingLauncher();
      PlatformInstaller.setInstance(installer);
      PlatformLauncher.setInstance(launcher);
    });

    tearDown(() {
      PlatformInstaller.setInstance(MacosPlatformInstaller());
      PlatformLauncher.setInstance(const MacosPlatformLauncher());
    });

    test('falls back to the browser when in-app install is unsupported',
        () async {
      installer = FakePlatformInstaller(supports: false);
      PlatformInstaller.setInstance(installer);

      final token = await UpdateService.downloadAndPrepare(
        info,
        onProgress: (_, _) {},
      );

      expect(token, isNull);
      expect(installer.preparedUrls, isEmpty);
      expect(launcher.openedUrls, <String>[info.releaseUrl]);
    });

    test('downloadAndInstall falls back to the browser when unsupported',
        () async {
      installer = FakePlatformInstaller(supports: false);
      PlatformInstaller.setInstance(installer);

      await UpdateService.downloadAndInstall(info, onProgress: (_, _) {});

      expect(installer.preparedUrls, isEmpty);
      expect(installer.launchedTokens, isEmpty);
      expect(launcher.openedUrls, <String>[info.releaseUrl]);
    });

    test('proceeds in-app on macOS and forwards url, tag and progress',
        () async {
      final progress = <double?>[];
      final statuses = <String>[];

      final token = await UpdateService.downloadAndPrepare(
        info,
        onProgress: (p, s) {
          progress.add(p);
          statuses.add(s);
        },
      );

      expect(token, 'tok-1');
      expect(
        installer.preparedUrls,
        <String>['https://example.test/app.zip'],
      );
      expect(installer.preparedTags, <String>['v2.0.0']);
      expect(progress, contains(0.5));
      expect(statuses, contains('Downloading…'));
      expect(launcher.openedUrls, isEmpty);
    });

    test('passes an empty url when the release has no download asset',
        () async {
      const noAsset = UpdateInfo(
        version: '2.0.0',
        tagName: 'v2.0.0',
        releaseUrl: 'https://example.test/release/v2.0.0',
        releaseNotes: 'notes',
      );

      final token = await UpdateService.downloadAndPrepare(
        noAsset,
        onProgress: (_, _) {},
      );

      expect(token, 'tok-1');
      expect(installer.preparedUrls, <String>['']);
      expect(launcher.openedUrls, isEmpty);
    });

    test('downloadAndInstall runs the full prepare + launch flow', () async {
      await UpdateService.downloadAndInstall(info, onProgress: (_, _) {});

      expect(installer.preparedTags, <String>['v2.0.0']);
      expect(installer.launchedTokens, <String>['tok-1']);
      expect(launcher.openedUrls, isEmpty);
    });

    test('applyUpdate delegates the launch token to the installer', () async {
      await UpdateService.applyUpdate('tok-1');
      expect(installer.launchedTokens, <String>['tok-1']);
    });
  });
}

class _RecordingLauncher extends PlatformLauncher {
  final List<String> openedUrls = <String>[];

  @override
  Future<void> openUrl(String url) async {
    openedUrls.add(url);
  }

  @override
  Future<void> revealInFinder(String path) async {}

  @override
  Future<void> openTerminal(String workdir) async {}
}
