import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/timer_plugin.dart';

BoardPanelInstance _panel() {
  return const BoardPanelInstance(
    id: 'timer-editor',
    type: TimerPlugin.kTypeId,
    title: 'Timer',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 360),
    state: <String, dynamic>{
      'duration': 300,
      'remaining': 300,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': '',
      'lastTick': 0,
    },
  );
}

Future<void> _pumpTimer(
  WidgetTester tester,
  List<Map<String, dynamic>> updates,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 360,
          child: Builder(
            builder: (context) => const TimerPlugin().buildContent(
              context,
              _panel(),
              BoardPanelRenderContext(
                isSelected: false,
                onFocus: () {},
                onDelete: () {},
                onUpdateState: updates.add,
                onShowEditor: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('editor renders quick timers and saves or cancels edits', (
    tester,
  ) async {
    final updates = <Map<String, dynamic>>[];
    await _pumpTimer(tester, updates);

    await tester.tap(find.text('05:00'));
    await tester.pump();

    expect(find.text('min'), findsOneWidget);
    expect(find.text('sec'), findsOneWidget);
    expect(find.text('1 min'), findsOneWidget);
    expect(find.text('5 min'), findsOneWidget);
    expect(find.text('60 min'), findsOneWidget);
    expect(find.text('Label (optional)'), findsOneWidget);

    await tester.tap(find.text('15 min'));
    await tester.pump();
    expect(updates.single['duration'], 900);
    expect(updates.single['remaining'], 900);
    expect(updates.single['isRunning'], isFalse);

    await tester.tap(find.text('05:00'));
    await tester.pump();
    await tester.enterText(find.byType(TextField).at(0), '2');
    await tester.enterText(find.byType(TextField).at(1), '30');
    await tester.enterText(find.byType(TextField).at(2), 'Focus block');
    await tester.tap(find.text('Set'));
    await tester.pump();

    expect(updates.last['duration'], 150);
    expect(updates.last['remaining'], 150);
    expect(updates.last['label'], 'Focus block');

    await tester.tap(find.text('05:00'));
    await tester.pump();
    final updateCount = updates.length;
    await tester.tap(find.text('Cancel'));
    await tester.pump();
    expect(find.text('Set'), findsNothing);
    expect(updates, hasLength(updateCount));
  });
}
