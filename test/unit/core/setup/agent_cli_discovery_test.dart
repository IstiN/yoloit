import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/setup/agent_cli_discovery.dart';

void main() {
  group('AgentCliDiscovery', () {
    test('extendedEnvironment includes kimi-code bin on macOS', () {
      if (!Platform.isMacOS) return;
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      PlatformShell.setInstance(MacosPlatformShell(homeOverride: home));
      addTearDown(() => PlatformShell.setInstance(const MacosPlatformShell()));

      final path = AgentCliDiscovery.extendedEnvironment()['PATH'] ?? '';
      expect(path.split(':'), contains('$home/.kimi-code/bin'));
      expect(path.split(':'), contains('$home/.local/bin'));
    });

    test('findKnownLocation resolves kimi and cursor-agent paths', () async {
      final home = Platform.environment['HOME'];
      if (home == null || home.isEmpty) return;

      final kimiPath = '$home/.kimi-code/bin/kimi';
      if (File(kimiPath).existsSync()) {
        expect(await AgentCliDiscovery.findExecutable('kimi'), kimiPath);
      }

      final cursorAgentPath = '$home/.local/bin/cursor-agent';
      if (File(cursorAgentPath).existsSync()) {
        expect(
          await AgentCliDiscovery.findExecutable('cursor-agent'),
          cursorAgentPath,
        );
      }
    });
  });
}
