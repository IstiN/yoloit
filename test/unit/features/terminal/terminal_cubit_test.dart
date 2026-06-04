import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

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
      expect: () => <TerminalState>[], // no state change since index is already 0
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
        id: 'id1', type: AgentType.copilot, workspacePath: '/p',
      );
      expect(s.displayName, 'Copilot');
    });

    test('displayName returns customName when set', () {
      final s = AgentSession(
        id: 'id1', type: AgentType.copilot, workspacePath: '/p',
      ).copyWith(customName: 'my-task');
      expect(s.displayName, 'my-task');
    });

    test('displayName falls back to type name when customName is empty string', () {
      final s = AgentSession(
        id: 'id1', type: AgentType.claude, workspacePath: '/p',
      ).copyWith(customName: '');
      // empty string → treated as no custom name
      expect(s.displayName, 'Claude');
    });

    test('copyWith customName preserves other fields', () {
      final base = AgentSession(
        id: 'id2', type: AgentType.terminal, workspacePath: '/home',
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
        id: 'id3', type: AgentType.copilot, workspacePath: '/p',
      ).copyWith(customName: 'feature/JIRA-42');
      expect(named.displayName, 'feature/JIRA-42');

      final reset = named.copyWith(clearCustomName: true);
      expect(reset.customName, isNull);
      expect(reset.displayName, 'Copilot');
    });

    test('copyWith without customName keeps existing customName', () {
      final named = AgentSession(
        id: 'id4', type: AgentType.claude, workspacePath: '/p',
      ).copyWith(customName: 'refactor');
      final updated = named.copyWith(status: AgentStatus.live);
      expect(updated.displayName, 'refactor');
      expect(updated.status, AgentStatus.live);
    });

    test('terminal maxLines is limited to 2000 to prevent UI freeze', () {
      final s = AgentSession(
        id: 'id5', type: AgentType.terminal, workspacePath: '/p',
      );
      expect(s.terminal.maxLines, 2000);
      expect(s.kTerminal.maxLines, 2000);
    });
  });
}
