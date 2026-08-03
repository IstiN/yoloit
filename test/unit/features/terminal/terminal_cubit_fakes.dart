import 'dart:async';

import 'package:mocktail/mocktail.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/data/logging_service.dart';
import 'package:yoloit/features/terminal/data/remote_yoloit_terminal_backend.dart';
import 'package:yoloit/features/terminal/data/session_persistence_service.dart';
import 'package:yoloit/features/terminal/data/terminal_backend.dart';
import 'package:yoloit/features/terminal/data/terminal_backend_service.dart';
import 'package:yoloit/features/terminal/data/tmux_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_backend_mode.dart';
import 'package:yoloit/features/workspaces/data/agent_workspace_dir_service.dart';
import 'package:yoloit/features/workspaces/data/workspace_secrets_service.dart';

class MockTerminalBackendService extends Mock
    implements TerminalBackendService {}

class MockSessionPersistenceService extends Mock
    implements SessionPersistenceService {}

class MockLoggingService extends Mock implements LoggingService {}

class MockTmuxService extends Mock implements TmuxService {}

class MockAgentConfigService extends Mock implements AgentConfigService {}

class MockWorkspaceSecretsService extends Mock
    implements WorkspaceSecretsService {}

class MockAgentWorkspaceDirService extends Mock
    implements AgentWorkspaceDirService {}

/// Hook service that never touches the filesystem: events are pushed manually.
class FakeAgentHookService extends AgentHookService {
  FakeAgentHookService() : super(pollInterval: const Duration(days: 1));

  final _controller = StreamController<HookEvent>.broadcast(sync: true);

  var startCalls = 0;
  var stopCalls = 0;

  @override
  Stream<HookEvent> get events => _controller.stream;

  @override
  void start() => startCalls++;

  @override
  void stop() => stopCalls++;

  void emitEvent(HookEvent event) => _controller.add(event);
}

/// A launched fake PTY: tests drive [output] and [exitCode] manually.
class FakePty {
  // ignore: close_sinks — owned/closed by individual tests.
  final output = StreamController<String>(sync: true);
  final exitCompleter = Completer<int>();

  TerminalProcess get process =>
      TerminalProcess(output: output.stream, exitCode: exitCompleter.future);
}

/// Bundles all mocked dependencies of [TerminalCubit] with sane defaults so
/// tests never touch the filesystem, real PTYs, or the network.
class TerminalCubitHarness {
  TerminalCubitHarness() {
    registerFallbackValue(AgentType.copilot);
    registerFallbackValue(<AgentSession>[]);
    registerFallbackValue(<String>[]);
    registerFallbackValue(<String, String>{});
    registerFallbackValue(
      RemoteYoloitTerminalBackend(
        remoteInfo: (
          url: 'http://localhost:8787',
          token: null,
          boardId: '',
          revision: null,
        ),
      ),
    );

    when(
      () => backend.launch(
        sessionId: any(named: 'sessionId'),
        workspacePath: any(named: 'workspacePath'),
        label: any(named: 'label'),
        extraEnv: any(named: 'extraEnv'),
      ),
    ).thenAnswer((invocation) async {
      final id = invocation.namedArguments[#sessionId] as String;
      final pty = FakePty();
      ptys[id] = pty;
      return pty.process;
    });
    when(
      () => backend.launch(
        sessionId: any(named: 'sessionId'),
        workspacePath: any(named: 'workspacePath'),
        backendOverride: any(named: 'backendOverride'),
      ),
    ).thenAnswer((invocation) async {
      final id = invocation.namedArguments[#sessionId] as String;
      final pty = FakePty();
      ptys[id] = pty;
      return pty.process;
    });
    when(() => backend.modeFor(any())).thenReturn(TerminalBackendMode.local);
    when(() => backend.write(any(), any())).thenReturn(null);
    when(() => backend.resize(any(), any(), any())).thenReturn(null);
    when(() => backend.kill(any())).thenAnswer((_) async {});

    when(() => persistence.load(any())).thenAnswer((_) async => []);
    when(() => persistence.save(any(), any())).thenAnswer((_) async {});

    when(() => logging.init()).thenAnswer((_) async {});
    when(() => logging.startSession(any(), any())).thenAnswer((_) async {});
    when(() => logging.endSession(any())).thenAnswer((_) async {});
    when(() => logging.write(any(), any())).thenReturn(null);

    when(() => tmux.init()).thenAnswer((_) async {});

    when(() => agentConfig.load()).thenAnswer((_) async => []);
    when(() => agentConfig.defaultAgentType).thenReturn(AgentType.copilot);
    when(
      () => agentConfig.effectiveLaunchCommand(any()),
    ).thenReturn('copilot --allow-all');

    when(
      () => secretsService.load(any()),
    ).thenAnswer((_) async => <String, String>{});

    when(
      () => workspaceDirs.readWorktreeContexts(any(), any(), any()),
    ).thenAnswer((_) async => null);
    when(() => workspaceDirs.createAgentDir(any(), any(), any())).thenAnswer((
      invocation,
    ) async {
      final workspaceId = invocation.positionalArguments[0] as String;
      final agentId = invocation.positionalArguments[1] as String;
      return '/agent-dirs/$workspaceId/$agentId';
    });
    when(
      () => workspaceDirs.deleteAgentDir(any(), any()),
    ).thenAnswer((_) async {});
  }

  final backend = MockTerminalBackendService();
  final persistence = MockSessionPersistenceService();
  final logging = MockLoggingService();
  final tmux = MockTmuxService();
  final agentConfig = MockAgentConfigService();
  final secretsService = MockWorkspaceSecretsService();
  final workspaceDirs = MockAgentWorkspaceDirService();
  final hookService = FakeAgentHookService();

  /// Launched fake PTYs keyed by session id.
  final ptys = <String, FakePty>{};

  /// Workspace paths passed to the hook installer.
  final hookInstallPaths = <String>[];

  TerminalCubit buildCubit() => TerminalCubit(
    backendService: backend,
    persistence: persistence,
    logging: logging,
    tmux: tmux,
    hookService: hookService,
    agentConfig: agentConfig,
    secretsService: secretsService,
    workspaceDirs: workspaceDirs,
    hookInstaller: (path) async => hookInstallPaths.add(path),
  );

  SavedSession savedSession(
    String id, {
    AgentType type = AgentType.copilot,
    String workspacePath = '/tmp/ws1',
    String? workspaceId,
    String? customName,
  }) => SavedSession(
    id: id,
    type: type,
    workspacePath: workspacePath,
    workspaceId: workspaceId,
    customName: customName,
  );
}
