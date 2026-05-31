import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/features/terminal/data/runtime_terminal_client.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';

void main() {
  tearDown(() {
    PlatformShell.setInstance(const MacosPlatformShell());
  });

  test('runtime terminal backend sends enriched PATH to daemon', () async {
    PlatformShell.setInstance(
      const MacosPlatformShell(homeOverride: '/Users/test'),
    );
    final client = _FakeRuntimeTerminalClient();
    final backend = RuntimeTerminalBackend(client: client);

    await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
      extraEnv: {'CUSTOM': 'value'},
    );

    expect(client.lastEnv?['CUSTOM'], 'value');
    expect(client.lastEnv?['TERM'], 'xterm-256color');
    expect(client.lastEnv?['COLORTERM'], 'truecolor');
    final path = client.lastEnv?['PATH'] ?? '';
    expect(path.split(':'), contains('/Users/test/.local/bin'));
    expect(path.split(':'), contains('/opt/homebrew/bin'));
  });
}

class _FakeRuntimeTerminalClient extends RuntimeTerminalClient {
  _FakeRuntimeTerminalClient() : super(runtimeHome: '/tmp/yoloit-test-runtime');

  Map<String, String>? lastEnv;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<bool> createSession({
    required String sessionId,
    required String cwd,
    String? command,
    Map<String, String> env = const {},
    int cols = 120,
    int rows = 30,
  }) async {
    lastEnv = env;
    return false;
  }

  @override
  Stream<String> streamSession(String sessionId) => const Stream.empty();
}
