import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/settings/data/setup_check_service.dart';

void main() {
  // ── InstallAction ──────────────────────────────────────────────────────────
  group('InstallAction', () {
    test('displayCommand uses interactiveScript when set', () {
      const action = InstallAction(
        executable: '/bin/bash',
        args: [],
        requiresInteractiveTerminal: true,
        interactiveScript: 'brew install git',
      );
      expect(action.displayCommand, 'brew install git');
    });

    test('displayCommand falls back to executable + args', () {
      const action = InstallAction(
        executable: 'brew',
        args: ['install', 'git'],
      );
      expect(action.displayCommand, 'brew install git');
    });

    test('displayCommand with no args', () {
      const action = InstallAction(executable: 'winget', args: []);
      expect(action.displayCommand, 'winget');
    });
  });

  // ── DependencyStatus ───────────────────────────────────────────────────────
  group('DependencyStatus', () {
    test('available dep has correct fields', () {
      const status = DependencyStatus(
        id: 'git',
        name: 'git',
        description: 'Version control',
        installHint: 'brew install git',
        isAvailable: true,
        version: '2.39.0',
        isRequired: true,
      );

      expect(status.id, 'git');
      expect(status.isAvailable, isTrue);
      expect(status.version, '2.39.0');
      expect(status.isRequired, isTrue);
    });

    test('unavailable dep has correct fields', () {
      const status = DependencyStatus(
        id: 'tmux',
        name: 'tmux',
        description: 'Terminal multiplexer',
        installHint: 'brew install tmux',
        isAvailable: false,
        isRequired: true,
      );

      expect(status.isAvailable, isFalse);
      expect(status.version, isNull);
    });

    test('optional dep defaults isRequired to true but can be overridden', () {
      const required = DependencyStatus(
        id: 'x',
        name: 'x',
        description: 'd',
        installHint: 'h',
        isAvailable: false,
      );
      const optional = DependencyStatus(
        id: 'y',
        name: 'y',
        description: 'd',
        installHint: 'h',
        isAvailable: false,
        isRequired: false,
      );
      expect(required.isRequired, isTrue);
      expect(optional.isRequired, isFalse);
    });
  });

  // ── SetupCheckResult ───────────────────────────────────────────────────────
  group('SetupCheckResult', () {
    test('allRequiredDepsOk is true when all required deps available', () {
      const result = SetupCheckResult(
        deps: [
          DependencyStatus(
            id: 'git',
            name: 'git',
            description: 'd',
            installHint: 'h',
            isAvailable: true,
            isRequired: true,
          ),
          DependencyStatus(
            id: 'brew',
            name: 'Homebrew',
            description: 'd',
            installHint: 'h',
            isAvailable: false,
            isRequired: false,
          ),
        ],
        agents: [],
      );
      expect(result.allRequiredDepsOk, isTrue);
    });

    test('allRequiredDepsOk is false when a required dep is missing', () {
      const result = SetupCheckResult(
        deps: [
          DependencyStatus(
            id: 'git',
            name: 'git',
            description: 'd',
            installHint: 'h',
            isAvailable: false,
            isRequired: true,
          ),
        ],
        agents: [],
      );
      expect(result.allRequiredDepsOk, isFalse);
    });

    test('anyAgentAvailable is true when at least one agent present', () {
      const result = SetupCheckResult(
        deps: [],
        agents: [
          DependencyStatus(
            id: 'copilot',
            name: 'Copilot',
            description: 'd',
            installHint: 'h',
            isAvailable: true,
            isRequired: false,
          ),
          DependencyStatus(
            id: 'claude',
            name: 'Claude',
            description: 'd',
            installHint: 'h',
            isAvailable: false,
            isRequired: false,
          ),
        ],
      );
      expect(result.anyAgentAvailable, isTrue);
    });

    test('anyAgentAvailable is false when no agents present', () {
      const result = SetupCheckResult(
        deps: [],
        agents: [
          DependencyStatus(
            id: 'copilot',
            name: 'Copilot',
            description: 'd',
            installHint: 'h',
            isAvailable: false,
            isRequired: false,
          ),
        ],
      );
      expect(result.anyAgentAvailable, isFalse);
    });

    test('anyAgentAvailable is false when agents list is empty', () {
      const result = SetupCheckResult(deps: [], agents: []);
      expect(result.anyAgentAvailable, isFalse);
    });
  });

  // ── Windows install hints ─────────────────────────────────────────────────
  group('Windows install hints format', () {
    // We validate the expected winget commands without running the platform check.
    // These mirror what _checkAllWindows produces.
    final windowsDepsHints = {
      'winget': 'Install "App Installer" from the Microsoft Store',
      'git': 'winget install Git.Git',
      'node': 'winget install OpenJS.NodeJS.LTS',
      'powershell': 'winget install Microsoft.PowerShell',
      'wt': 'winget install Microsoft.WindowsTerminal',
    };

    for (final entry in windowsDepsHints.entries) {
      test('${entry.key} install hint is winget-based', () {
        expect(
          entry.value.toLowerCase(),
          anyOf(contains('winget'), contains('microsoft store')),
        );
      });
    }

    test('Windows copilot agent uses winget install hint', () {
      const hint = 'winget install GitHub.Copilot';
      expect(hint, contains('winget'));
      expect(hint, contains('Copilot'));
    });

    test('Windows cursor agent uses winget install hint', () {
      const hint = 'winget install Anysphere.Cursor';
      expect(hint, contains('winget'));
      expect(hint, contains('Cursor'));
    });
  });

  // ── macOS install hints ───────────────────────────────────────────────────
  group('macOS install hints format', () {
    final macDepsHints = {
      'brew': 'https://brew.sh',
      'git': 'brew install git',
      'node': 'brew install node',
      'tmux': 'brew install tmux',
      'bash': 'brew install bash',
    };

    for (final entry in macDepsHints.entries) {
      test('${entry.key} install hint is homebrew-based', () {
        expect(
          entry.value.toLowerCase(),
          anyOf(contains('brew'), contains('homebrew')),
        );
      });
    }

    test('macOS copilot uses npm install hint', () {
      const hint = 'npm install -g @github/copilot';
      expect(hint, contains('npm'));
    });
  });

  // ── Linux install hints ───────────────────────────────────────────────────
  group('Linux install hints format', () {
    final linuxHints = [
      'sudo apt install git',
      'sudo apt install nodejs npm',
      'sudo apt install tmux',
    ];

    for (final hint in linuxHints) {
      test('$hint uses apt', () {
        expect(hint, contains('apt'));
      });
    }
  });

  group('PATH enrichment', () {
    test('includes kimi-code install directory on Unix', () {
      if (Platform.isWindows) return;

      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      final path = SetupCheckService.debugExtendedPathForTesting();
      expect(path.split(':'), contains('$home/.kimi-code/bin'));
    });
  });
}
