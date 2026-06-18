import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_shell.dart';
import 'package:yoloit/core/services/resource_monitor_service.dart';
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

    expect(client.lastCommand, isNotNull);
    expect(client.lastEnv?['CUSTOM'], 'value');
    expect(client.lastEnv?['TERM'], 'xterm-256color');
    expect(client.lastEnv?['COLORTERM'], 'truecolor');
    final path = client.lastEnv?['PATH'] ?? '';
    expect(path.split(':'), contains('/Users/test/.local/bin'));
    expect(path.split(':'), contains('/opt/homebrew/bin'));
  });
  test('runtime terminal backend reattaches without killing existing session',
      () async {
    final client = _FakeRuntimeTerminalClient(existingOnCreate: true);
    final backend = RuntimeTerminalBackend(client: client);

    final process = await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
    );

    expect(client.killCalls, isEmpty);
    expect(process.attachedExisting, isTrue);
  });

  test('runtime terminal backend forceNewShell kills existing session', () async {
    final client = _FakeRuntimeTerminalClient(existingOnCreate: true);
    final backend = RuntimeTerminalBackend(client: client);

    final process = await backend.launch(
      sessionId: 'session-1',
      workspacePath: '/tmp/workspace',
      forceNewShell: true,
    );

    expect(client.killCalls, ['session-1']);
    expect(client.createCalls, 2);
    expect(process.attachedExisting, isFalse);
  });

  test('runtime terminal backend registers shell session for resource monitor',
      () async {
    final client = _FakeRuntimeTerminalClient();
    final backend = RuntimeTerminalBackend(client: client);
    const metadata = ResourceSessionMetadata(
      kind: 'terminal',
      boardId: 'board-1',
      boardName: 'Work',
      panelId: 'panel-1',
      panelTitle: 'Shell',
      panelType: 'board.terminal',
      provider: 'terminal',
    );

    await backend.launch(
      sessionId: 'board_terminal_1',
      workspacePath: '/tmp/workspace',
      label: 'Shell',
      metadata: metadata,
    );

    expect(
      ResourceMonitorService.instance.registeredPids,
      contains(42),
    );
    expect(
      ResourceMonitorService.instance.metadataForRuntimeSession(
        'board_terminal_1',
      )?.panelId,
      'panel-1',
    );

    ResourceMonitorService.instance.unregisterSession(42);
    ResourceMonitorService.instance.unregisterRuntimeSession('board_terminal_1');
  });
}

class _FakeRuntimeTerminalClient extends RuntimeTerminalClient {
  _FakeRuntimeTerminalClient({this.existingOnCreate = false})
    : super(runtimeHome: '/tmp/yoloit-test-runtime');

  final bool existingOnCreate;
  Map<String, String>? lastEnv;
  String? lastCommand;
  final killCalls = <String>[];
  var createCalls = 0;

  @override
  Future<void> ensureStarted() async {}

  @override
  Future<RuntimeSessionCreateResult> createSession({
    required String sessionId,
    required String cwd,
    String? command,
    Map<String, String> env = const {},
    int cols = 120,
    int rows = 30,
  }) async {
    createCalls++;
    lastEnv = env;
    lastCommand = command;
    return RuntimeSessionCreateResult(
      existing: existingOnCreate && createCalls == 1,
      shellPid: 42,
    );
  }

  @override
  Future<void> kill(String sessionId) async {
    killCalls.add(sessionId);
  }

  @override
  Stream<String> streamSession(String sessionId) => const Stream.empty();
}
