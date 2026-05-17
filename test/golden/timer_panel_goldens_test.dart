import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_plugin.dart';

Widget _timerShell({
  required BoardPanelInstance panel,
  BoardPanelRenderContext? renderContext,
}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: SizedBox(
        width: 300,
        height: 320,
        child: Builder(
          builder: (ctx) => const TimerPlugin().buildContent(
            ctx,
            panel,
            renderContext ?? _noopContext(),
          ),
        ),
      ),
    ),
  );
}

BoardPanelRenderContext _noopContext() {
  return BoardPanelRenderContext(
    isSelected: false,
    onFocus: () {},
    onDelete: () {},
    onUpdateState: (_) {},
    onShowEditor: () {},
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'timer_golden',
      type: 'board.timer',
      title: 'Timer',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 320),
      state: state,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — TimerPanel', () {
    testGoldens('timer panel idle', (tester) async {
      await tester.pumpWidgetBuilder(
        _timerShell(panel: _panel()),
        surfaceSize: const Size(300, 320),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'timer_panel_idle');
    });

    testGoldens('timer panel with label', (tester) async {
      await tester.pumpWidgetBuilder(
        _timerShell(
          panel: _panel(state: {
            'duration': 600,
            'remaining': 600,
            'label': 'Pomodoro',
          }),
        ),
        surfaceSize: const Size(300, 320),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'timer_panel_with_label');
    });

    testGoldens('timer panel running', (tester) async {
      await tester.pumpWidgetBuilder(
        _timerShell(
          panel: _panel(state: {
            'duration': 300,
            'remaining': 180,
            'isRunning': true,
            'lastTick': DateTime.now().millisecondsSinceEpoch,
          }),
        ),
        surfaceSize: const Size(300, 320),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'timer_panel_running');
    });

    testGoldens('timer panel completed', (tester) async {
      await tester.pumpWidgetBuilder(
        _timerShell(
          panel: _panel(state: {
            'duration': 300,
            'remaining': 0,
            'completed': true,
          }),
        ),
        surfaceSize: const Size(300, 320),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'timer_panel_completed');
    });

    testGoldens('timer panel edit mode', (tester) async {
      await tester.pumpWidgetBuilder(
        _timerShell(panel: _panel()),
        surfaceSize: const Size(300, 320),
      );
      // Tap the time display to enter edit mode
      await tester.tap(find.text('05:00'));
      await tester.pump();
      await screenMatchesGolden(tester, 'timer_panel_edit_mode');
    });
  });
}
