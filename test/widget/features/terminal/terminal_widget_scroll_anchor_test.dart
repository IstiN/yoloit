import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/models/terminal_render_engine.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;

/// Regression tests for the terminal scroll-preserve machine: while the user
/// is scrolled up, a 50ms timer pins the viewport to a captured anchor so
/// streaming output does not move it. Returning to the bottom must disarm
/// that anchor — otherwise the timer keeps yanking the viewport back up and
/// fights xterm's stick-to-bottom follow (visible as scroll jitter).
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

  testWidgets('returning to the bottom disarms the scroll preserve anchor', (
    tester,
  ) async {
    final key = GlobalKey<TerminalWidgetState>();
    final session = AgentSession(
      id: 'sess_scroll_anchor',
      type: AgentType.copilot,
      workspacePath: '/project',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 600,
            height: 140,
            child: TerminalWidget(
              key: key,
              session: session,
              isActive: true,
              autoRequestFocus: false,
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    for (var i = 0; i < 80; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump();
    await tester.pump();

    final terminalView = tester.widget<TerminalView>(
      find.byType(TerminalView),
    );
    final scrollController = terminalView.scrollController!;
    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();

    // Scroll up: the preserve anchor arms and pins the viewport while output
    // streams.
    key.currentState!.scrollPageUp();
    await tester.pump();
    final parked = scrollController.offset;
    expect(parked, lessThan(scrollController.position.maxScrollExtent));

    for (var i = 80; i < 90; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    expect(scrollController.offset, parked);

    // Scroll back to the bottom: the anchor must disarm so the next output
    // burst follows stick-to-bottom instead of being yanked back up. A
    // page-down that lands short of the bottom legitimately keeps the anchor
    // armed, so page down until the bottom is actually reached.
    for (var i = 0; i < 10; i++) {
      if (scrollController.offset >=
          scrollController.position.maxScrollExtent) {
        break;
      }
      key.currentState!.scrollPageDown();
      await tester.pump();
    }
    expect(
      scrollController.offset,
      scrollController.position.maxScrollExtent,
    );

    for (var i = 90; i < 100; i++) {
      session.terminal.write('line $i\r\n');
    }
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump();
    await tester.pump();

    expect(
      scrollController.offset,
      scrollController.position.maxScrollExtent,
    );
  });
}
