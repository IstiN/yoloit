import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/terminal/board_terminal_full_view.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

/// Widget tests for the modern fullscreen terminal view: floating auto-hide
/// control bar, font size controls and the close affordance.
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

  AgentSession newSession([String id = 'sess_fullview']) => AgentSession(
    id: id,
    type: AgentType.copilot,
    workspacePath: '/project',
  );

  Future<void> openFullView(WidgetTester tester, AgentSession session) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed:
                    () => showGeneralDialog<void>(
                      context: context,
                      barrierColor: Colors.black,
                      pageBuilder:
                          (ctx, _, __) => BoardTerminalFullView(
                            session: session,
                            title: 'My Terminal',
                          ),
                    ),
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Future<void> openFullViewWithTabs(
    WidgetTester tester,
    List<BoardTerminalFullViewTab> tabs,
    AgentSession selected,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder:
              (context) => ElevatedButton(
                onPressed:
                    () => showGeneralDialog<void>(
                      context: context,
                      barrierColor: Colors.black,
                      pageBuilder:
                          (ctx, _, __) => BoardTerminalFullView(
                            session: selected,
                            title: 'Selected',
                            tabs: tabs,
                          ),
                    ),
                child: const Text('open'),
              ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  TerminalWidgetState terminalState(WidgetTester tester) {
    return tester.state<TerminalWidgetState>(find.byType(TerminalWidget));
  }

  testWidgets('shows the control bar with the title and closes via the close '
      'button', (tester) async {
    await openFullView(tester, newSession());

    expect(find.text('My Terminal'), findsOneWidget);
    expect(find.byType(TerminalWidget), findsOneWidget);

    await tester.tap(find.byTooltip('Close full view'));
    await tester.pumpAndSettle();

    expect(find.text('My Terminal'), findsNothing);
  });

  testWidgets('font size buttons change the terminal font size', (
    tester,
  ) async {
    await openFullView(tester, newSession());
    final before = terminalState(tester).currentFontSize;

    await tester.tap(find.byTooltip('Increase font size'));
    await tester.pump();
    expect(terminalState(tester).currentFontSize, before + 1);

    await tester.tap(find.byTooltip('Decrease font size'));
    await tester.pump();
    expect(terminalState(tester).currentFontSize, before);
  });

  testWidgets('debug pane is hidden by default and toggles on', (
    tester,
  ) async {
    await openFullView(tester, newSession());

    expect(find.byTooltip('Dump terminal state'), findsNothing);

    await tester.tap(find.byTooltip('Show debug pane'));
    await tester.pump();

    expect(find.byTooltip('Dump terminal state'), findsOneWidget);
    expect(find.text('MouseOn'), findsOneWidget);
  });

  testWidgets('shows a tab per board terminal with the opening terminal '
      'selected', (tester) async {
    final sessionA = newSession('sess_a');
    final sessionB = newSession('sess_b');
    final sessionC = newSession('sess_c');
    await openFullViewWithTabs(
      tester,
      [
        BoardTerminalFullViewTab(
          panelId: 'p-a',
          title: 'Alpha',
          session: sessionA,
        ),
        BoardTerminalFullViewTab(
          panelId: 'p-b',
          title: 'Beta',
          session: sessionB,
        ),
        BoardTerminalFullViewTab(
          panelId: 'p-c',
          title: 'Gamma',
          session: sessionC,
        ),
      ],
      sessionB,
    );

    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(find.text('Gamma'), findsOneWidget);
    // The opening tab is the one bound to the terminal widget.
    expect(
      tester.widget<TerminalWidget>(find.byType(TerminalWidget)).session.id,
      'sess_b',
    );
  });

  testWidgets('tapping another tab switches the terminal session', (
    tester,
  ) async {
    final sessionA = newSession('sess_a');
    final sessionB = newSession('sess_b');
    await openFullViewWithTabs(
      tester,
      [
        BoardTerminalFullViewTab(
          panelId: 'p-a',
          title: 'Alpha',
          session: sessionA,
        ),
        BoardTerminalFullViewTab(
          panelId: 'p-b',
          title: 'Beta',
          session: sessionB,
        ),
      ],
      sessionA,
    );
    expect(
      tester.widget<TerminalWidget>(find.byType(TerminalWidget)).session.id,
      'sess_a',
    );

    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<TerminalWidget>(find.byType(TerminalWidget)).session.id,
      'sess_b',
    );
    // Only one terminal widget stays mounted — the inactive tab does not
    // keep rendering offscreen.
    expect(find.byType(TerminalWidget), findsOneWidget);
  });
}
