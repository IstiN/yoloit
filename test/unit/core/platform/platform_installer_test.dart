import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_installer.dart';

import '../../../helpers/fake_process_runner.dart';

void main() {
  tearDown(() {
    PlatformInstaller.setInstance(const MacosPlatformInstaller());
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
}
