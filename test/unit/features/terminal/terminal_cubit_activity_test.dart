import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/services/agent_hook_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_phase.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

import 'terminal_cubit_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TerminalCubitHarness harness;

  setUp(() {
    // Disable sounds so no real `afplay` processes are spawned.
    SharedPreferences.setMockInitialValues({
      'notifications.approvalSound': false,
      'notifications.completionSound': false,
    });
    harness = TerminalCubitHarness();
  });

  TerminalCubit initCubit(FakeAsync async) {
    final cubit = harness.buildCubit();
    cubit.initialize();
    async.flushMicrotasks();
    return cubit;
  }

  TerminalLoaded loaded(TerminalCubit cubit) => cubit.state as TerminalLoaded;

  AgentSession sessionOf(TerminalCubit cubit, String id) =>
      loaded(cubit).allSessions.firstWhere((s) => s.id == id);

  AgentPhase? phaseOf(TerminalCubit cubit, String id) =>
      sessionOf(cubit, id).hookPhase;

  /// Fires all pending one-shot timers and cancels recurring ones.
  void settle(FakeAsync async, TerminalCubit cubit) {
    async.elapse(const Duration(seconds: 20));
    cubit.close();
    async.flushMicrotasks();
  }

  /// Restores a single persisted session so its id is deterministic.
  void restoreSession(
    FakeAsync async,
    TerminalCubit cubit, {
    String id = 's1',
    AgentType type = AgentType.copilot,
  }) {
    when(
      () => harness.persistence.load('ws1'),
    ).thenAnswer((_) async => [harness.savedSession(id, type: type)]);
    cubit.setActiveWorkspace(workspaceId: 'ws1', workspacePath: '/tmp/ws1');
    async.flushMicrotasks();
  }

  HookEvent hookEvent(String event, {String cwd = '/tmp/ws1', String? tool}) =>
      HookEvent(
        event: event,
        workspacePath: cwd,
        workspaceHash: 'h',
        tool: tool,
        timestamp: 1,
      );

  group('hook events', () {
    test(
      'userPromptSubmitted sets ThinkingPhase and auto-clears after 15s',
      () {
        fakeAsync((async) {
          final cubit = initCubit(async);
          restoreSession(async, cubit);

          harness.hookService.emitEvent(hookEvent('userPromptSubmitted'));
          expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

          async.elapse(const Duration(seconds: 14));
          expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());
          async.elapse(const Duration(seconds: 2));
          expect(phaseOf(cubit, 's1'), isNull);

          settle(async, cubit);
        });
      },
    );

    test('preToolUse sets ToolPhase, postToolUse clears it', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        harness.hookService.emitEvent(hookEvent('preToolUse', tool: 'bash'));
        final phase = phaseOf(cubit, 's1');
        expect(phase, isA<ToolPhase>());
        expect((phase! as ToolPhase).toolName, 'bash');

        harness.hookService.emitEvent(hookEvent('postToolUse'));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('sessionEnd sets DonePhase and auto-clears after 3s', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        harness.hookService.emitEvent(hookEvent('sessionEnd'));
        expect(phaseOf(cubit, 's1'), isA<DonePhase>());

        async.elapse(const Duration(seconds: 4));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('errorOccurred sets ErrorPhase', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        harness.hookService.emitEvent(hookEvent('errorOccurred'));
        expect(phaseOf(cubit, 's1'), isA<ErrorPhase>());

        settle(async, cubit);
      });
    });

    test('postToolUse does not clear AwaitingApprovalPhase', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        // Enter awaiting-approval via PTY pattern detection.
        harness.ptys['s1']!.output.add('Do you want to allow this?');
        expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

        harness.hookService.emitEvent(hookEvent('postToolUse'));
        expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

        // Fallback timer clears it once the PTY goes quiet.
        async.elapse(const Duration(seconds: 16));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('hook events match sessions by normalized workspace path', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        // Trailing slash is normalized away.
        harness.hookService.emitEvent(
          hookEvent('userPromptSubmitted', cwd: '/tmp/ws1/'),
        );
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        harness.hookService.emitEvent(hookEvent('postToolUse'));
        expect(phaseOf(cubit, 's1'), isNull);

        // Subdirectory of the session path also matches.
        harness.hookService.emitEvent(
          hookEvent('userPromptSubmitted', cwd: '/tmp/ws1/lib/src'),
        );
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        settle(async, cubit);
      });
    });

    test('hook events for unknown or empty paths are ignored', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        harness.hookService.emitEvent(
          hookEvent('userPromptSubmitted', cwd: '/somewhere/else'),
        );
        expect(phaseOf(cubit, 's1'), isNull);

        harness.hookService.emitEvent(
          hookEvent('userPromptSubmitted', cwd: ''),
        );
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('hook events with no sessions do nothing', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        harness.hookService.emitEvent(hookEvent('userPromptSubmitted'));
        expect(loaded(cubit).sessions, isEmpty);
        settle(async, cubit);
      });
    });
  });

  group('PTY activity detection', () {
    test('spinner chars set ThinkingPhase and idle timeout clears it', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);
        final pty = harness.ptys['s1']!;

        pty.output.add('○ compiling');
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        // Second spinner chunk restarts the idle timer (no duplicate phase).
        async.elapse(const Duration(seconds: 4));
        pty.output.add('◎ still working');
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        // Idle timeout is 5s for copilot: 4s in, the restart keeps it alive.
        async.elapse(const Duration(seconds: 4));
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());
        async.elapse(const Duration(seconds: 2));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('spinner does not override an active hook phase', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);

        harness.hookService.emitEvent(hookEvent('userPromptSubmitted'));
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        // Spinner only restarts the idle timer; phase stays hook-owned.
        harness.ptys['s1']!.output.add('○ compiling');
        expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

        // PTY idle timer (5s) clears the ThinkingPhase.
        async.elapse(const Duration(seconds: 6));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test('approval dialog sets AwaitingApprovalPhase and fallback timer '
        'clears it', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);
        final pty = harness.ptys['s1']!;

        pty.output.add('Do you want to allow directory access?');
        expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

        // Non-approval PTY activity while awaiting restarts the fallback
        // clear timer (dialog still open, agent keeps redrawing).
        async.elapse(const Duration(seconds: 10));
        pty.output.add('still waiting');
        expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

        // 15s after the last chunk the phase is cleared.
        async.elapse(const Duration(seconds: 10));
        expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());
        async.elapse(const Duration(seconds: 6));
        expect(phaseOf(cubit, 's1'), isNull);

        settle(async, cubit);
      });
    });

    test(
      'approval pattern split across chunks is detected via tail buffer',
      () {
        fakeAsync((async) {
          final cubit = initCubit(async);
          restoreSession(async, cubit);
          final pty = harness.ptys['s1']!;

          pty.output.add('... Do you want to al');
          expect(phaseOf(cubit, 's1'), isNull);

          pty.output.add('low this?');
          expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

          settle(async, cubit);
        });
      },
    );

    test(
      'Enter pressed while awaiting approval transitions to ThinkingPhase',
      () {
        fakeAsync((async) {
          final cubit = initCubit(async);
          restoreSession(async, cubit);
          final pty = harness.ptys['s1']!;

          // No-op for unknown sessions and sessions not awaiting approval.
          cubit.onTerminalEnterPressed('ghost');
          cubit.onTerminalEnterPressed('s1');
          expect(phaseOf(cubit, 's1'), isNull);

          pty.output.add('Do you want to allow this?');
          expect(phaseOf(cubit, 's1'), isA<AwaitingApprovalPhase>());

          cubit.onTerminalEnterPressed('s1');
          expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

          // The approval fallback timer was cancelled, so nothing clears the
          // ThinkingPhase until new PTY activity arrives.
          async.elapse(const Duration(seconds: 16));
          expect(phaseOf(cubit, 's1'), isA<ThinkingPhase>());

          settle(async, cubit);
        });
      },
    );

    test('done prompt while thinking flashes DonePhase then clears', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit, id: 'c1', type: AgentType.claude);

        harness.hookService.emitEvent(hookEvent('userPromptSubmitted'));
        expect(phaseOf(cubit, 'c1'), isA<ThinkingPhase>());

        harness.ptys['c1']!.output.add('some result\n> ');
        expect(phaseOf(cubit, 'c1'), isA<DonePhase>());

        async.elapse(const Duration(seconds: 4));
        expect(phaseOf(cubit, 'c1'), isNull);

        settle(async, cubit);
      });
    });

    test('done prompt without thinking does nothing', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit, id: 'c1', type: AgentType.claude);

        harness.ptys['c1']!.output.add('idle prompt\n> ');
        expect(phaseOf(cubit, 'c1'), isNull);

        settle(async, cubit);
      });
    });

    test('PTY output is batched and flushed on a timer', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);
        final pty = harness.ptys['s1']!;

        pty.output.add('hello world\n');
        expect(sessionOf(cubit, 's1').recentLines, isEmpty);

        async.elapse(const Duration(milliseconds: 60));
        expect(sessionOf(cubit, 's1').recentLines, contains('hello world'));

        settle(async, cubit);
      });
    });

    test('large PTY chunk flushes immediately without waiting', () {
      fakeAsync((async) {
        final cubit = initCubit(async);
        restoreSession(async, cubit);
        final pty = harness.ptys['s1']!;

        pty.output.add('x' * 20000);
        expect(sessionOf(cubit, 's1').recentLines.join(), contains('xxxx'));

        settle(async, cubit);
      });
    });
  });
}
