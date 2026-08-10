import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    AgentConfigService.instance.setTerminalRenderEngineForTesting(
      TerminalRenderEngine.xterm,
    );
  });

  tearDown(() {
    TerminalWidgetState.enableTerminalDiagnostics = false;
  });

  Future<List<String>> pumpDiagnosticsTerminal(
    WidgetTester tester,
    AgentSession session, {
    String? debugLabel,
  }) async {
    final logs = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 400,
            child: TerminalWidget(
              session: session,
              isActive: true,
              debugLabel: debugLabel,
              debugLogSink: logs.add,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return logs;
  }

  group('TerminalWidget xterm diagnostics dump', () {
    testWidgets('buffer changes schedule a debounced diagnostics dump', (
      tester,
    ) async {
      final session = AgentSession(
        id: 'sess_diag',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      final logs = await pumpDiagnosticsTerminal(
        tester,
        session,
        debugLabel: 'diag',
      );

      session.terminal.write('hello diagnostics\r\n');
      await tester.pump();
      // The dump is debounced; nothing xterm-specific has been logged yet.
      expect(logs.where((m) => m.contains('xterm active=')), isEmpty);

      // Fire the 2s debounce timer.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      expect(
        logs.any((m) => m.startsWith('buffer-change ')),
        isTrue,
        reason: logs.join('\n'),
      );
      final xtermLines =
          logs.where((m) => m.contains('xterm active=true')).toList();
      expect(xtermLines, isNotEmpty);
      // Summary line carries the visible range, cursor and scrollback info.
      expect(xtermLines.first, contains('visible='));
      expect(xtermLines.first, contains('cursor='));
      expect(xtermLines.first, contains('scrollBack='));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('verbose mode dumps per-row cell diagnostics', (tester) async {
      TerminalWidgetState.enableTerminalDiagnostics = true;
      final session = AgentSession(
        id: 'sess_diag_verbose',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      final logs = await pumpDiagnosticsTerminal(tester, session);

      session.terminal.write('verbose row dump\r\n');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();

      final rowLines = logs.where((m) => m.startsWith('xterm row=')).toList();
      expect(rowLines, isNotEmpty, reason: logs.join('\n'));
      expect(rowLines.first, contains('wrapped='));
      expect(rowLines.first, contains('cells='));
      await tester.pump(const Duration(milliseconds: 500));
    });

    testWidgets('inactive terminal does not schedule a dump', (tester) async {
      final session = AgentSession(
        id: 'sess_diag_inactive',
        type: AgentType.copilot,
        workspacePath: '/project',
      );
      final logs = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 400,
              child: TerminalWidget(
                session: session,
                isActive: false,
                debugLabel: 'diag',
                debugLogSink: logs.add,
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      session.terminal.write('no dump while inactive\r\n');
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump();

      expect(logs.where((m) => m.contains('xterm active=')), isEmpty);
      await tester.pump(const Duration(milliseconds: 500));
    });
  });
}
