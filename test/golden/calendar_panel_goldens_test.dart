import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';
import 'package:yoloit/features/calendar/ui/calendar_panel_content.dart';

class _FakeStorage extends CalendarEventStorage {
  const _FakeStorage(this.events);

  final List<CalendarEvent> events;

  @override
  Future<List<CalendarEvent>> loadEvents(String panelId) async => List.of(events);

  @override
  Future<CalendarEvent> upsertEvent(String panelId, CalendarEvent event) async =>
      event;

  @override
  Future<bool> deleteEvent(String panelId, String eventId) async => true;
}

Widget _calendarShell(
  BoardPanelInstance panel, {
  List<CalendarEvent> events = const [],
  double width = 900,
  double height = 600,
}) {
  return MaterialApp(
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      body: SizedBox(
        width: width,
        height: height,
        child: CalendarPanelContent(
          panel: panel,
          renderContext: BoardPanelRenderContext(
            isSelected: false,
            onFocus: () {},
            onDelete: () {},
            onUpdateState: (_) {},
            onShowEditor: () {},
          ),
          storage: _FakeStorage(events),
        ),
      ),
    ),
  );
}

BoardPanelInstance _panel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'cal-golden',
      type: 'board.calendar',
      title: 'Calendar',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 720, height: 520),
      state: state,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — CalendarPanelContent', () {
    testGoldens('month view empty', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(_panel()),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_month_empty');
    });

    testGoldens('month view with event', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(
          _panel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
          events: [
            CalendarEvent(
              id: 'ev-1',
              title: 'Sprint Planning',
              start: DateTime(2026, 6, 19, 10),
              end: DateTime(2026, 6, 19, 11),
            ),
          ],
        ),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_month_with_event');
    });

    testGoldens('week view', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(
          _panel(state: {'view': 'week', 'focusedDate': '2026-06-19T00:00:00.000'}),
        ),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_week_view');
    });

    testGoldens('day view', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(
          _panel(state: {'view': 'day', 'focusedDate': '2026-06-19T00:00:00.000'}),
          events: [
            CalendarEvent(
              id: 'ev-2',
              title: 'Standup',
              start: DateTime(2026, 6, 19, 9, 30),
              end: DateTime(2026, 6, 19, 10),
            ),
          ],
        ),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_day_view');
    });

    testGoldens('new event dialog', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(
          _panel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
        ),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_new_event_dialog');
    });

    testGoldens('edit event dialog', (tester) async {
      await tester.pumpWidgetBuilder(
        _calendarShell(
          _panel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
          events: [
            CalendarEvent(
              id: 'ev-3',
              title: 'Retrospective',
              start: DateTime(2026, 6, 19, 15),
              end: DateTime(2026, 6, 19, 16),
            ),
          ],
        ),
        surfaceSize: const Size(900, 600),
      );
      await tester.pump();
      await tester.longPress(find.text('Retrospective'));
      await tester.pump();
      await screenMatchesGolden(tester, 'calendar_panel_edit_event_dialog');
    });
  });
}
