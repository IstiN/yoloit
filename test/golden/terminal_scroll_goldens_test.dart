import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoxterm/xterm.dart' hide TerminalState;
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';
import 'package:yoloit/features/terminal/ui/terminal_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testGoldens('terminal scrollback moves after trackpad pan-zoom', (
    tester,
  ) async {
    final session = AgentSession(
      id: 'terminal_scroll_golden',
      type: AgentType.copilot,
      workspacePath: '/project',
    );
    final outputs = <String>[];

    await tester.pumpWidgetBuilder(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 520,
              height: 180,
              child: ScrollableCardMarker(
                child: ScrollableCardRegion(
                  child: TerminalWidget(
                    session: session,
                    isActive: true,
                    terminalOutputWriter:
                        (sessionId, data) => outputs.add(data),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      surfaceSize: const Size(560, 220),
    );
    await tester.pump();

    for (var i = 0; i < 90; i++) {
      session.terminal.write(
        'history-line-${i.toString().padLeft(3, '0')} '
        'abcdefghijklmnopqrstuvwxyz\r\n',
      );
    }
    // Two pumps are required because xterm render.dart now batches
    // layout updates via addPostFrameCallback.
    await tester.pump();
    await tester.pump();

    final terminalView = tester.widget<TerminalView>(find.byType(TerminalView));
    final scrollController = terminalView.scrollController!;
    expect(scrollController.position.maxScrollExtent, greaterThan(0));

    scrollController.jumpTo(scrollController.position.maxScrollExtent);
    await tester.pump();
    final before = scrollController.offset;
    final position = tester.getCenter(find.byType(TerminalView));

    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(pointer: 1, position: position),
    );
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 1,
        position: position,
        panDelta: const Offset(0, 96),
      ),
    );
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(pointer: 1, position: position),
    );
    await tester.pump();

    expect(scrollController.offset, lessThan(before));
    expect(outputs, isEmpty);
    await screenMatchesGolden(
      tester,
      'terminal_scroll_after_trackpad_pan_zoom',
    );
  });
}
