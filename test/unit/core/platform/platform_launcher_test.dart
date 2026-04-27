import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_launcher.dart';

import '../../../helpers/fake_process_runner.dart';

void main() {
  tearDown(() {
    // Reset singleton.
    PlatformLauncher.setInstance(const MacosPlatformLauncher());
  });

  group('MacosPlatformLauncher', () {
    late FakeProcessRunner fakeRunner;
    late MacosPlatformLauncher launcher;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      launcher = MacosPlatformLauncher(processRunner: fakeRunner.run);
    });

    test('openUrl calls open with the url', () async {
      await launcher.openUrl('https://example.com');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'open');
      expect(call.arguments, ['https://example.com']);
    });

    test('revealInFinder calls open -R with the path', () async {
      await launcher.revealInFinder('/some/file.txt');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'open');
      expect(call.arguments, ['-R', '/some/file.txt']);
    });

    test('openTerminal calls osascript twice', () async {
      await launcher.openTerminal('/my/project');
      expect(fakeRunner.calls.length, 2);
      expect(fakeRunner.calls[0].executable, 'osascript');
      expect(fakeRunner.calls[1].executable, 'osascript');
    });

    test('openTerminal second osascript activates Terminal', () async {
      await launcher.openTerminal('/my/project');
      final activateArgs = fakeRunner.calls[1].arguments;
      expect(activateArgs.join(' '), contains('activate'));
    });
  });

  group('LinuxPlatformLauncher', () {
    late FakeProcessRunner fakeRunner;
    late LinuxPlatformLauncher launcher;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      // Mock which returning success for gnome-terminal.
      fakeRunner.mockResult('which', exitCode: 0, stdout: '/usr/bin/gnome-terminal');
      launcher = LinuxPlatformLauncher(processRunner: fakeRunner.run);
    });

    test('openUrl calls xdg-open with the url', () async {
      await launcher.openUrl('https://example.com');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'xdg-open');
      expect(call.arguments, ['https://example.com']);
    });

    test('revealInFinder calls xdg-open on parent directory', () async {
      await launcher.revealInFinder('/some/dir/file.txt');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'xdg-open');
      expect(call.arguments.first, '/some/dir');
    });

    test('openTerminal tries gnome-terminal first', () async {
      await launcher.openTerminal('/my/project');
      // First call: which gnome-terminal; second: gnome-terminal --working-directory=
      expect(fakeRunner.calls[0].executable, 'which');
      expect(fakeRunner.calls[0].arguments, ['gnome-terminal']);
      expect(fakeRunner.calls[1].executable, 'gnome-terminal');
    });
  });

  group('WindowsPlatformLauncher', () {
    late FakeProcessRunner fakeRunner;
    late WindowsPlatformLauncher launcher;

    setUp(() {
      fakeRunner = FakeProcessRunner();
      launcher = WindowsPlatformLauncher(processRunner: fakeRunner.run);
    });

    test('openUrl calls cmd /c start with url', () async {
      await launcher.openUrl('https://example.com');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'cmd');
      expect(call.arguments, containsAll(['/c', 'start']));
      expect(call.arguments, contains('https://example.com'));
    });

    test('revealInFinder calls explorer /select, with path', () async {
      await launcher.revealInFinder(r'C:\Users\test\file.txt');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'explorer');
      expect(call.arguments, contains('/select,'));
    });

    test('openTerminal uses wt.exe when available', () async {
      // FakeProcessRunner returns exitCode 0 by default, so where wt.exe succeeds.
      await launcher.openTerminal(r'C:\my\project');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'wt.exe');
      expect(call.arguments, contains('-d'));
    });

    test('openTerminal falls back to cmd when wt.exe is not found', () async {
      fakeRunner.mockResult('where', exitCode: 1, stdout: '');
      await launcher.openTerminal(r'C:\my\project');
      final call = fakeRunner.lastCall!;
      expect(call.executable, 'cmd');
      expect(call.arguments, contains('/K'));
    });
  });

  group('PlatformLauncher.instance', () {
    test('can be overridden for testing', () {
      final fakeRunner = FakeProcessRunner();
      final fake = MacosPlatformLauncher(processRunner: fakeRunner.run);
      PlatformLauncher.setInstance(fake);
      expect(PlatformLauncher.instance, same(fake));
    });
  });
}
