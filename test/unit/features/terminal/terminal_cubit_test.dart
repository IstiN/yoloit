import 'package:bloc_test/bloc_test.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

import 'terminal_cubit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('TerminalCubit', () {
    test('initial state is TerminalInitial', () {
      expect(TerminalCubit().state, isA<TerminalInitial>());
    });

    blocTest<TerminalCubit, TerminalState>(
      'initialize() emits TerminalLoaded with empty sessions',
      build: () => TerminalCubit(),
      act: (cubit) => cubit.initialize(),
      expect: () => [
        isA<TerminalLoaded>()
            .having((s) => s.sessions, 'sessions', isEmpty)
            .having((s) => s.activeIndex, 'activeIndex', 0),
      ],
    );

    blocTest<TerminalCubit, TerminalState>(
      'switchTab updates activeIndex',
      build: () => TerminalCubit(),
      seed: () => const TerminalLoaded(sessions: [], activeIndex: 0),
      act: (cubit) => cubit.switchTab(0), // no-op with empty sessions
      expect: () =>
          <TerminalState>[], // no state change since index is already 0
    );

    blocTest<TerminalCubit, TerminalState>(
      'switchTab ignores out-of-bounds index',
      build: () => TerminalCubit(),
      seed: () => const TerminalLoaded(sessions: [], activeIndex: 0),
      act: (cubit) => cubit.switchTab(5),
      expect: () => <TerminalState>[],
    );

    test('TerminalLoaded activeSession returns null for empty sessions', () {
      const state = TerminalLoaded(sessions: [], activeIndex: 0);
      expect(state.activeSession, isNull);
    });

    test('AgentType displayName is correct', () {
      expect(AgentType.copilot.displayName, 'Copilot');
      expect(AgentType.claude.displayName, 'Claude');
      expect(AgentType.pi.displayName, 'Pi');
      expect(AgentType.terminal.displayName, 'Terminal');
    });

    test('AgentType command is correct', () {
      expect(AgentType.copilot.command, 'copilot');
      expect(AgentType.claude.command, 'claude');
      expect(AgentType.pi.command, 'pi');
      expect(AgentType.terminal.command, 'shell');
    });

    test('AgentType launchCommand includes --allow-all for copilot', () {
      expect(AgentType.copilot.launchCommand, 'copilot --allow-all');
      expect(AgentType.claude.launchCommand, 'claude');
      expect(AgentType.pi.launchCommand, 'pi');
      expect(AgentType.terminal.launchCommand, isEmpty);
    });

    test('AgentType has icon labels', () {
      for (final type in AgentType.values) {
        expect(type.iconLabel, isNotEmpty);
      }
    });
  });

  group('AgentSession', () {
    test('displayName returns type name when no customName', () {
      final s = AgentSession(
        id: 'id1',
        type: AgentType.copilot,
        workspacePath: '/p',
      );
      expect(s.displayName, 'Copilot');
    });

    test('displayName returns customName when set', () {
      final s = AgentSession(
        id: 'id1',
        type: AgentType.copilot,
        workspacePath: '/p',
      ).copyWith(customName: 'my-task');
      expect(s.displayName, 'my-task');
    });

    test(
      'displayName falls back to type name when customName is empty string',
      () {
        final s = AgentSession(
          id: 'id1',
          type: AgentType.claude,
          workspacePath: '/p',
        ).copyWith(customName: '');
        // empty string → treated as no custom name
        expect(s.displayName, 'Claude');
      },
    );

    test('copyWith customName preserves other fields', () {
      final base = AgentSession(
        id: 'id2',
        type: AgentType.terminal,
        workspacePath: '/home',
        workspaceId: 'ws_x',
      );
      final renamed = base.copyWith(customName: 'shell-debug');
      expect(renamed.id, 'id2');
      expect(renamed.type, AgentType.terminal);
      expect(renamed.workspaceId, 'ws_x');
      expect(renamed.displayName, 'shell-debug');
    });

    test('copyWith clearCustomName resets to type name', () {
      final named = AgentSession(
        id: 'id3',
        type: AgentType.copilot,
        workspacePath: '/p',
      ).copyWith(customName: 'feature/JIRA-42');
      expect(named.displayName, 'feature/JIRA-42');

      final reset = named.copyWith(clearCustomName: true);
      expect(reset.customName, isNull);
      expect(reset.displayName, 'Copilot');
    });

    test('copyWith without customName keeps existing customName', () {
      final named = AgentSession(
        id: 'id4',
        type: AgentType.claude,
        workspacePath: '/p',
      ).copyWith(customName: 'refactor');
      final updated = named.copyWith(status: AgentStatus.live);
      expect(updated.displayName, 'refactor');
      expect(updated.status, AgentStatus.live);
    });

    test('terminal maxLines is limited to 2000 to prevent UI freeze', () {
      final s = AgentSession(
        id: 'id5',
        type: AgentType.terminal,
        workspacePath: '/p',
      );
      expect(s.terminal.maxLines, 2000);
    });
  });

  group('TerminalCubit with fakes', () {
    late TerminalCubitHarness harness;

    setUp(() {
      harness = TerminalCubitHarness();
    });

    TerminalCubit initCubit(FakeAsync async) {
      final cubit = harness.buildCubit();
      cubit.initialize();
      async.flushMicrotasks();
      return cubit;
    }

    TerminalLoaded loaded(TerminalCubit cubit) => cubit.state as TerminalLoaded;

    /// Fires all pending one-shot timers and cancels recurring ones.
    void settle(FakeAsync async, TerminalCubit cubit) {
      async.elapse(const Duration(seconds: 20));
      cubit.close();
      async.flushMicrotasks();
    }

    void restoreTwoSessions(FakeAsync async, TerminalCubit cubit) {
      when(() => harness.persistence.load('ws1')).thenAnswer(
        (_) async => [
          harness.savedSession('saved_a'),
          harness.savedSession('saved_b'),
        ],
      );
      cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
      async.flushMicrotasks();
      // Each restore awaits the auto-run delay (1200ms) plus the 200ms
      // stagger before the next session is spawned.
      async.elapse(const Duration(milliseconds: 2000));
      async.flushMicrotasks();
    }

    test('initialize starts hook service and emits empty loaded state', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        expect(harness.hookService.startCalls, 1);
        expect(loaded(cubit).sessions, isEmpty);
        expect(loaded(cubit).activeIndex, 0);
        settle(async, cubit);
      });
    });

    test('setActiveWorkspace spawns default agent when nothing persisted', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();

        final state = loaded(cubit);
        expect(state.sessions, hasLength(1));
        final session = state.sessions.single;
        expect(session.type, AgentType.copilot);
        expect(session.workspacePath, '/tmp/ws1');
        expect(session.workspaceId, 'ws1');
        expect(session.status, AgentStatus.live);
        expect(state.activeIndex, 0);
        verify(
          () => harness.backend.launch(
            sessionId: session.id,
            workspacePath: '/tmp/ws1',
            label: 'Copilot',
            extraEnv: null,
          ),
        ).called(1);
        expect(harness.hookInstallPaths, ['/tmp/ws1']);

        // Auto-run writes the agent launch command after a short delay.
        async.elapse(const Duration(milliseconds: 1300));
        verify(
          () => harness.backend.write(session.id, 'copilot --allow-all\n'),
        ).called(1);
        verify(
          () => harness.persistence.save(any(), 'ws1'),
        ).called(greaterThan(0));

        settle(async, cubit);
      });
    });

    test('setActiveWorkspace restores persisted sessions with their ids', () {
      fakeAsync((async) {
        when(() => harness.persistence.load('ws1')).thenAnswer(
          (_) async => [
            harness.savedSession('saved_a', customName: 'alpha'),
            harness.savedSession('saved_b', type: AgentType.claude),
          ],
        );
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();
        // Restore loop awaits auto-run (1200ms) + 200ms stagger per session.
        async.elapse(const Duration(milliseconds: 2000));
        async.flushMicrotasks();

        final state = loaded(cubit);
        expect(state.sessions.map((s) => s.id), ['saved_a', 'saved_b']);
        expect(state.sessions[0].customName, 'alpha');
        expect(state.sessions[0].status, AgentStatus.live);
        expect(state.sessions[1].type, AgentType.claude);
        expect(state.activeIndex, 1);
        verify(
          () => harness.workspaceDirs.readWorktreeContexts('ws1', 'saved_a', [
            '/tmp/ws1',
          ]),
        ).called(1);
        verify(
          () => harness.backend.launch(
            sessionId: 'saved_b',
            workspacePath: '/tmp/ws1',
            label: 'Claude',
            extraEnv: null,
          ),
        ).called(1);

        settle(async, cubit);
      });
    });

    test(
      'setActiveWorkspace reuses running sessions and restores tab index',
      () {
        fakeAsync((async) {
          final cubit = initCubit(async);
          restoreTwoSessions(async, cubit);
          expect(loaded(cubit).sessions, hasLength(2));

          cubit.switchTab(0);
          async.flushMicrotasks();
          expect(loaded(cubit).activeIndex, 0);

          cubit.setActiveWorkspace(
            workspaceId: 'ws2',
            workspacePath: '/tmp/ws2',
          );
          async.flushMicrotasks();
          expect(loaded(cubit).sessions, hasLength(1));
          expect(loaded(cubit).sessions.single.workspaceId, 'ws2');

          // Switching back shows the already-running ws1 sessions, no respawn.
          cubit.setActiveWorkspace(
            workspaceId: 'ws1',
            workspacePath: '/tmp/ws1',
          );
          async.flushMicrotasks();
          final state = loaded(cubit);
          expect(state.sessions.map((s) => s.id), ['saved_a', 'saved_b']);
          expect(state.activeIndex, 0);
          verify(
            () => harness.backend.launch(
              sessionId: any(named: 'sessionId'),
              workspacePath: '/tmp/ws1',
              label: any(named: 'label'),
              extraEnv: any(named: 'extraEnv'),
            ),
          ).called(2); // only the two initial restores

          settle(async, cubit);
        });
      },
    );

    test('closeSession kills backend, removes session, and persists', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);

        cubit.closeSession('saved_a');

        final state = loaded(cubit);
        expect(state.sessions.map((s) => s.id), ['saved_b']);
        expect(state.activeIndex, 0); // clamped from 1
        expect(state.allSessions.map((s) => s.id), ['saved_b']);
        verify(() => harness.backend.kill('saved_a')).called(1);
        verify(() => harness.logging.endSession('saved_a')).called(1);
        verify(
          () => harness.persistence.save(any(), 'ws1'),
        ).called(greaterThan(0));

        settle(async, cubit);
      });
    });

    test('closeSession deletes agent dir for worktree sessions', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();
        cubit.spawnSession(
          type: AgentType.terminal,
          workspacePath: '/tmp/ws1',
          workspaceId: 'ws1',
          savedSessionId: 'wt1',
          worktreeContexts: const {'/repo': '/wt'},
        );
        async.flushMicrotasks();

        final worktree = loaded(
          cubit,
        ).sessions.firstWhere((s) => s.id == 'wt1');
        expect(worktree.workspacePath, '/agent-dirs/ws1/wt1');
        verify(
          () => harness.workspaceDirs.createAgentDir('ws1', 'wt1', {
            '/repo': '/wt',
          }),
        ).called(1);

        cubit.closeSession('wt1');
        expect(loaded(cubit).sessions.map((s) => s.id), isNot(contains('wt1')));
        verify(
          () => harness.workspaceDirs.deleteAgentDir('ws1', 'wt1'),
        ).called(1);

        settle(async, cubit);
      });
    });

    test('closeSession is a no-op before initialize', () {
      final cubit = harness.buildCubit();
      cubit.closeSession('ghost');
      verifyNever(() => harness.backend.kill(any()));
      cubit.close();
    });

    test('loadPersistedMetadataForWorkspaces adds idle stubs for other '
        'workspaces', () {
      fakeAsync((async) {
        when(() => harness.persistence.load('ws2')).thenAnswer(
          (_) async => [
            harness.savedSession(
              'meta1',
              workspacePath: '/tmp/ws2',
              workspaceId: 'ws2',
            ),
            harness.savedSession('meta2', workspacePath: '/tmp/ws2'),
          ],
        );
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();

        cubit.loadPersistedMetadataForWorkspaces(['ws1', 'ws2', 'ws3']);
        async.flushMicrotasks();

        final state = loaded(cubit);
        expect(state.sessions, hasLength(1)); // only ws1 visible
        expect(state.allSessions, hasLength(3));
        final meta1 = state.allSessions.firstWhere((s) => s.id == 'meta1');
        expect(meta1.status, AgentStatus.idle);
        expect(meta1.workspaceId, 'ws2');
        final meta2 = state.allSessions.firstWhere((s) => s.id == 'meta2');
        // Falls back to the queried workspace id when none persisted.
        expect(meta2.workspaceId, 'ws2');

        settle(async, cubit);
      });
    });

    test('loadPersistedMetadataForWorkspaces skips already-known sessions', () {
      fakeAsync((async) {
        when(
          () => harness.persistence.load('ws2'),
        ).thenAnswer((_) async => [harness.savedSession('meta1')]);
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();

        cubit.loadPersistedMetadataForWorkspaces(['ws2']);
        async.flushMicrotasks();
        expect(loaded(cubit).allSessions, hasLength(2));

        // Second call: id already known → no duplicate stubs.
        cubit.loadPersistedMetadataForWorkspaces(['ws2']);
        async.flushMicrotasks();
        expect(loaded(cubit).allSessions, hasLength(2));

        settle(async, cubit);
      });
    });

    test('loadPersistedMetadataForWorkspaces works before initialize', () {
      fakeAsync((async) {
        when(
          () => harness.persistence.load('ws9'),
        ).thenAnswer((_) async => [harness.savedSession('meta9')]);
        final cubit = harness.buildCubit();
        cubit.loadPersistedMetadataForWorkspaces(['ws9']);
        async.flushMicrotasks();

        final state = loaded(cubit);
        expect(state.sessions, isEmpty);
        expect(state.allSessions.single.id, 'meta9');
        expect(state.allSessions.single.status, AgentStatus.idle);
        cubit.close();
      });
    });

    test('PTY stream done/error marks sessions idle', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);
        expect(loaded(cubit).sessions, hasLength(2));

        harness.ptys['saved_a']!.output.close();
        harness.ptys['saved_b']!.output.addError(StateError('boom'));
        async.flushMicrotasks();

        final state = loaded(cubit);
        expect(state.sessions[0].status, AgentStatus.idle);
        expect(state.sessions[1].status, AgentStatus.idle);

        settle(async, cubit);
      });
    });

    test('sendInput forwards text to the backend', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);

        cubit.sendInput('saved_a', 'ls -la\n');
        verify(() => harness.backend.write('saved_a', 'ls -la\n')).called(1);

        settle(async, cubit);
      });
    });

    test('setActiveSessionById switches the active tab', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);
        expect(loaded(cubit).activeIndex, 1);

        cubit.setActiveSessionById('saved_a');
        expect(loaded(cubit).activeIndex, 0);

        // Unknown id and already-active id are no-ops.
        cubit.setActiveSessionById('ghost');
        cubit.setActiveSessionById('saved_a');
        expect(loaded(cubit).activeIndex, 0);

        settle(async, cubit);
      });
    });

    test('renameSession sets, trims, and clears custom names', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);

        cubit.renameSession('saved_a', '  build-bot  ');
        expect(loaded(cubit).sessions.first.customName, 'build-bot');
        verify(
          () => harness.persistence.save(any(), 'ws1'),
        ).called(greaterThan(0));

        cubit.renameSession('saved_a', '   ');
        expect(loaded(cubit).sessions.first.customName, isNull);

        // Unknown id is a no-op.
        cubit.renameSession('ghost', 'x');
        expect(loaded(cubit).sessions, hasLength(2));

        settle(async, cubit);
      });
    });

    test('updateSessionWorktree stores the new worktree path', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();
        cubit.spawnSession(
          type: AgentType.terminal,
          workspacePath: '/tmp/ws1',
          workspaceId: 'ws1',
          savedSessionId: 'wt1',
          worktreeContexts: const {'/repo': '/wt'},
        );
        async.flushMicrotasks();

        expect(cubit.updateSessionWorktree('ghost', '/repo', '/wt2'), isNull);

        final updated = cubit.updateSessionWorktree('wt1', '/repo', '/wt2');
        expect(updated, isNotNull);
        expect(updated!.worktreeContexts, {'/repo': '/wt2'});
        verify(
          () => harness.persistence.save(any(), 'ws1'),
        ).called(greaterThan(0));

        settle(async, cubit);
      });
    });

    test('resizeActiveTerminal resizes only the active session', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreTwoSessions(async, cubit);

        cubit.resizeActiveTerminal(120, 40);
        verify(() => harness.backend.resize('saved_b', 120, 40)).called(1);
        verifyNever(() => harness.backend.resize('saved_a', any(), any()));

        settle(async, cubit);
      });
    });

    test('resizeActiveTerminal is a no-op before initialize', () {
      final cubit = harness.buildCubit();
      cubit.resizeActiveTerminal(120, 40);
      verifyNever(() => harness.backend.resize(any(), any(), any()));
      cubit.close();
    });

    test(
      'closeSession with unknown id uses a fallback session for cleanup',
      () {
        fakeAsync((async) {
          final cubit = initCubit(async);
          restoreTwoSessions(async, cubit);

          cubit.closeSession('ghost');
          verify(() => harness.backend.kill('ghost')).called(1);
          verifyNever(() => harness.workspaceDirs.deleteAgentDir(any(), any()));
          expect(loaded(cubit).sessions, hasLength(2));

          settle(async, cubit);
        });
      },
    );

    test('createRemoteSession adds a remote shell session', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
        async.flushMicrotasks();

        cubit.createRemoteSession(
          remoteInfo: (
            url: 'http://localhost:8787',
            token: null,
            boardId: 'b1',
            revision: null,
          ),
          cwd: '/remote/dir',
          name: '  Pi Box  ',
        );
        async.flushMicrotasks();

        final remote = loaded(
          cubit,
        ).allSessions.firstWhere((s) => s.workspacePath == '/remote/dir');
        expect(remote.type, AgentType.terminal);
        expect(remote.customName, 'Pi Box');
        expect(remote.status, AgentStatus.live);
        verify(
          () => harness.backend.launch(
            sessionId: remote.id,
            workspacePath: '/remote/dir',
            backendOverride: any(named: 'backendOverride'),
          ),
        ).called(1);

        settle(async, cubit);
      });
    });
  });
}
