import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

/// Regression tests for the shared `terminal.onOutput`/`onResize` single-slot
/// bindings: multiple TerminalWidgets can attach to the same session (board
/// panel + full-view dialog + mindmap card). Closing the top widget must
/// restore the previous widget's binding instead of nulling the slots (which
/// killed keyboard input on the panel terminal after the full-view dialog
/// was dismissed).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    CanvasInteractionLock.instance.resetForTesting();
    AgentConfigService.instance.setTerminalRenderEngineForTesting(
      TerminalRenderEngine.xterm,
    );
  });

  tearDown(() {
    CanvasInteractionLock.instance.resetForTesting();
  });

  AgentSession newSession() => AgentSession(
    id: 'sess_binding',
    type: AgentType.copilot,
    workspacePath: '/project',
  );

  Widget shell(Widget child) => MaterialApp(
    home: Scaffold(
      body: SizedBox(width: 600, height: 400, child: child),
    ),
  );

  testWidgets(
    'closing a second TerminalWidget restores the first widget binding',
    (tester) async {
      final session = newSession();
      final outA = <String>[];
      final outB = <String>[];

      Widget build({required bool showB}) => shell(
        Column(
          children: [
            Expanded(
              child: TerminalWidget(
                session: session,
                isActive: true,
                autoRequestFocus: false,
                terminalOutputWriter: (id, data) => outA.add(data),
              ),
            ),
            if (showB)
              Expanded(
                child: TerminalWidget(
                  session: session,
                  isActive: true,
                  autoRequestFocus: false,
                  terminalOutputWriter: (id, data) => outB.add(data),
                ),
              ),
          ],
        ),
      );

      await tester.pumpWidget(build(showB: false));
      await tester.pump();

      session.terminal.textInput('a');
      expect(outA, ['a']);
      expect(outB, isEmpty);

      // Open the "full view": a second widget binds the same terminal and
      // (last binder wins) takes over the single-slot callbacks.
      await tester.pumpWidget(build(showB: true));
      await tester.pump();

      session.terminal.textInput('b');
      expect(outA, ['a']);
      expect(outB, ['b']);

      // Close the "full view": the second widget is disposed. Its unbind must
      // restore the first widget's callbacks, not null them out.
      await tester.pumpWidget(build(showB: false));
      await tester.pump();

      expect(session.terminal.onOutput, isNotNull);
      expect(session.terminal.onResize, isNotNull);

      session.terminal.textInput('c');
      expect(outA, ['a', 'c']);
      expect(outB, ['b']);
    },
  );

  testWidgets(
    'disposing the non-active widget keeps the active binding intact',
    (tester) async {
      final session = newSession();
      final outA = <String>[];
      final outB = <String>[];

      Widget build({required bool showA}) => shell(
        Column(
          children: [
            if (showA)
              Expanded(
                child: TerminalWidget(
                  session: session,
                  isActive: true,
                  autoRequestFocus: false,
                  terminalOutputWriter: (id, data) => outA.add(data),
                ),
              ),
            Expanded(
              child: TerminalWidget(
                session: session,
                isActive: true,
                autoRequestFocus: false,
                terminalOutputWriter: (id, data) => outB.add(data),
              ),
            ),
          ],
        ),
      );

      await tester.pumpWidget(build(showA: true));
      await tester.pump();

      // B bound last, so it is active. Disposing A (non-active) must not
      // touch the live slots.
      await tester.pumpWidget(build(showA: false));
      await tester.pump();

      expect(session.terminal.onOutput, isNotNull);
      session.terminal.textInput('x');
      expect(outA, isEmpty);
      expect(outB, ['x']);
    },
  );

  testWidgets(
    'closing the second widget re-syncs the terminal to the restored '
    'widget viewport size',
    (tester) async {
      final session = newSession();

      // A (panel) and B (full view) get clearly different heights, so the
      // shared terminal is resized whenever B's render object lays out.
      Widget build({required bool showB}) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 500,
            child: Column(
              children: [
                SizedBox(
                  height: 400,
                  child: TerminalWidget(
                    session: session,
                    isActive: true,
                    autoRequestFocus: false,
                  ),
                ),
                if (showB)
                  SizedBox(
                    height: 100,
                    child: TerminalWidget(
                      session: session,
                      isActive: true,
                      autoRequestFocus: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );

      await tester.pumpWidget(build(showB: false));
      await tester.pump(const Duration(milliseconds: 300));
      final panelHeight = session.terminal.viewHeight;

      await tester.pumpWidget(build(showB: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(session.terminal.viewHeight, lessThan(panelHeight));

      // Close B: the restored binding must re-push A's viewport size,
      // otherwise the panel keeps rendering at B's dimensions (blank /
      // clipped content until a manual resize).
      await tester.pumpWidget(build(showB: false));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(session.terminal.viewHeight, panelHeight);
    },
  );
}
