import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';

void main() {
  test('catalog provides OS-aware install scripts', () {
    final linuxScript = SetupCatalog.installScript(<String>[
      'git',
      'codex',
    ], SetupTargetOs.linux);

    expect(linuxScript, contains('apt-get install -y git'));
    expect(linuxScript, contains('npm install -g @openai/codex'));
    expect(linuxScript, contains('chatgpt.com/codex/install.sh'));
    expect(linuxScript, contains('==> [1]'));
    expect(linuxScript, contains('==> [2]'));
    expect(linuxScript, contains(r'failed: $code'));
  });

  test('catalog includes Kimi Code CLI install actions', () {
    final kimi = SetupCatalog.packages.singleWhere((pkg) => pkg.id == 'kimi');

    expect(kimi.name, 'Kimi Code CLI');
    expect(kimi.command, 'kimi');
    expect(
      kimi.installAction(SetupTargetOs.linux)?.command,
      contains('https://code.kimi.com/kimi-code/install.sh'),
    );
    expect(
      kimi.installAction(SetupTargetOs.windows)?.command,
      contains('https://code.kimi.com/kimi-code/install.ps1'),
    );
  });

  test('catalog includes Cursor Agent CLI package', () {
    final cursorAgent = SetupCatalog.packages.singleWhere(
      (pkg) => pkg.id == 'cursor-agent',
    );
    expect(cursorAgent.command, 'cursor-agent');
  });

  test('check snapshot serializes package install metadata', () {
    const snapshot = SetupCheckSnapshot(
      runtime: SetupRuntimeInfo(
        os: SetupTargetOs.linux,
        osLabel: 'Ubuntu',
        versionLabel: '24.04',
        packageManager: 'apt',
        homeDirectory: '/home/yolo',
      ),
      packages: <SetupPackageStatus>[
        SetupPackageStatus(
          id: 'codex',
          name: 'Codex CLI',
          category: SetupPackageCategory.agents,
          description: 'Agent',
          command: 'codex',
          required: false,
          available: false,
          installAction: SetupInstallAction(command: 'install codex'),
        ),
      ],
    );

    final restored = SetupCheckSnapshot.fromJson(snapshot.toJson());

    expect(restored.runtime.os, SetupTargetOs.linux);
    expect(restored.packages.single.id, 'codex');
    expect(restored.packages.single.installAction?.command, 'install codex');
  });

  group('package manager detection', () {
    test('detectRuntime reports the host platform details', () async {
      final runtime = await SetupCatalog.detectRuntime();

      expect(runtime.os, SetupTargetOs.macos);
      expect(runtime.osLabel, 'macOS');
      expect(runtime.packageManager, anyOf('brew', 'shell'));
      expect(runtime.homeDirectory, isNotEmpty);
    });

    test('macOS resolves to brew or shell', () async {
      expect(
        await SetupCatalog.packageManagerForOs(SetupTargetOs.macos),
        anyOf('brew', 'shell'),
      );
    });

    test('windows resolves to winget or shell', () async {
      expect(
        await SetupCatalog.packageManagerForOs(SetupTargetOs.windows),
        anyOf('winget', 'shell'),
      );
    });

    test('linux probes apt, dnf and pacman before shell', () async {
      expect(
        await SetupCatalog.packageManagerForOs(SetupTargetOs.linux),
        anyOf('apt', 'dnf', 'pacman', 'shell'),
      );
    });

    test('unknown OS always falls back to shell', () async {
      expect(
        await SetupCatalog.packageManagerForOs(SetupTargetOs.unknown),
        'shell',
      );
    });
  });
}
