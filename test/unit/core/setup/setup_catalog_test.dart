import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/setup/setup_catalog.dart';

void main() {
  test('catalog provides OS-aware install scripts', () {
    final linuxScript = SetupCatalog.installScript(<String>[
      'git',
      'codex',
    ], SetupTargetOs.linux);

    expect(linuxScript, contains('apt-get install -y git'));
    expect(linuxScript, contains('chatgpt.com/codex/install.sh'));
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
}
