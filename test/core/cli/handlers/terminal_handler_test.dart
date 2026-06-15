import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/terminal_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'test-panel-terminal',
      type: 'board.terminal',
      title: 'Terminal',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 600, height: 400),
      state: state,
    );

void main() {
  const handler = TerminalCliHandler();

  group('TerminalCliHandler — metadata', () {
    test('typeId is board.terminal', () {
      expect(handler.typeId, 'board.terminal');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll(<String>['config', 'set-dir', 'output']),
      );
    });
  });

  group('TerminalCliHandler — config action', () {
    test('config returns panel config map', () async {
      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: 'board_terminal_123',
            sessionName: 'yoloit',
            workingDir: '/Users/dev/project',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('config', {}, panel);
      expect(r.ok, isTrue);
      final config = r.data!['config'] as Map<String, dynamic>;
      expect(config['sessionId'], 'board_terminal_123');
      expect(config['sessionName'], 'yoloit');
      expect(config['workingDir'], '/Users/dev/project');
    });

    test('config returns empty map when state is empty', () async {
      final panel = _panel();
      final r = await handler.handleAction('config', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['config'], <String, dynamic>{});
    });
  });

  group('TerminalCliHandler — set-dir action', () {
    test('set-dir updates working directory', () async {
      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: '',
            sessionName: '',
            workingDir: '/old',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('set-dir', {'dir': '/new'}, panel);
      expect(r.ok, isTrue);
      final config = r.stateUpdate!['config'] as Map<String, dynamic>;
      expect(config['workingDir'], '/new');
    });

    test('set-dir without dir returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('set-dir', {}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('TerminalCliHandler — output action', () {
    tearDown(() {
      BoardTerminalSessionManager.instance.clearSessionsForTesting();
    });

    test('output returns ok=false when panel has no config', () async {
      final panel = _panel();
      final r = await handler.handleAction('output', {}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('not configured'));
    });

    test('output returns ok=false when session is not live', () async {
      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: 'board_terminal_missing',
            sessionName: 'yoloit',
            workingDir: '/Users/dev/project',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('output', {}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('is not live'));
    });

    test('output returns recent lines from live session', () async {
      const sessionId = 'board_terminal_abc';
      final session = AgentSession(
        id: sessionId,
        type: AgentType.terminal,
        workspacePath: '/Users/dev/project',
      );
      session.appendOutput('first line\nsecond line\nthird line\n');
      BoardTerminalSessionManager.instance.setSessionForTesting(
        sessionId,
        session,
      );

      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: sessionId,
            sessionName: 'yoloit',
            workingDir: '/Users/dev/project',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('output', {'limit': 2}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['sessionId'], sessionId);
      final lines = r.data!['lines'] as List<dynamic>;
      expect(lines.length, 2);
      expect(lines, contains('second line'));
      expect(lines, contains('third line'));
      expect(r.data!['limit'], 2);
    });

    test('output returns raw history when raw=true', () async {
      const sessionId = 'board_terminal_raw';
      final session = AgentSession(
        id: sessionId,
        type: AgentType.terminal,
        workspacePath: '/Users/dev/project',
      );
      session.appendOutput('\x1B[32mhello\x1B[0m\n');
      BoardTerminalSessionManager.instance.setSessionForTesting(
        sessionId,
        session,
      );

      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: sessionId,
            sessionName: 'yoloit',
            workingDir: '/Users/dev/project',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('output', {'raw': true}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['sessionId'], sessionId);
      expect(r.data!['raw'] as String, contains('\x1B[32mhello'));
    });

    test('output clamps limit to valid range', () async {
      const sessionId = 'board_terminal_limit';
      final session = AgentSession(
        id: sessionId,
        type: AgentType.terminal,
        workspacePath: '/Users/dev/project',
      );
      session.appendOutput('line\n');
      BoardTerminalSessionManager.instance.setSessionForTesting(
        sessionId,
        session,
      );

      final panel = _panel(
        state: {
          'config': const BoardTerminalConfig(
            sessionId: sessionId,
            sessionName: 'yoloit',
            workingDir: '/Users/dev/project',
          ).toJson(),
        },
      );
      final r = await handler.handleAction('output', {'limit': -5}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['limit'], 80);

      final r2 = await handler.handleAction('output', {'limit': 5000}, panel);
      expect(r2.ok, isTrue);
      expect(r2.data!['limit'], 300);
    });
  });

  group('TerminalCliHandler — unknown action', () {
    test('unknown action returns ok=false', () async {
      final panel = _panel();
      final r = await handler.handleAction('restart', {}, panel);
      expect(r.ok, isFalse);
    });
  });
}
