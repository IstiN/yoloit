import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late BoardPanelRenderContext renderContext;
  Map<String, dynamic>? lastState;

  setUp(() {
    lastState = null;
    renderContext = BoardPanelRenderContext(
      isSelected: false,
      onFocus: () {},
      onDelete: () {},
      onUpdateState: (state) => lastState = state,
      onShowEditor: () {},
    );
  });

  BoardPanelInstance newPanel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'cal-widget-1',
        type: 'board.calendar',
        title: 'Calendar',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
        state: state,
      );

  Future<void> pumpCalendar(
    WidgetTester tester,
    BoardPanelInstance panel, {
    List<CalendarEvent> events = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CalendarPanelContent(
            panel: panel,
            renderContext: renderContext,
            storage: _FakeStorage(events),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('renders month view by default', (tester) async {
    await pumpCalendar(tester, newPanel());
    expect(find.byType(CalendarPanelContent), findsOneWidget);
    expect(find.text('Month'), findsWidgets);
  });

  testWidgets('switches to week view', (tester) async {
    await pumpCalendar(tester, newPanel());
    await tester.tap(find.text('Month').first);
    await tester.pump();
    await tester.tap(find.text('Week').last);
    await tester.pump();
    expect(lastState?['view'], 'week');
  });

  testWidgets('loads and displays events', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
      events: [
        CalendarEvent(
          id: 'ev-1',
          title: 'Team Sync',
          start: DateTime(2026, 6, 19, 10),
          end: DateTime(2026, 6, 19, 11),
        ),
      ],
    );
    expect(find.text('Team Sync'), findsOneWidget);
    expect(lastState?['eventCount'], 1);
  });

  testWidgets('navigates previous and next month', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(state: {'focusedDate': '2026-06-15T00:00:00.000'}),
    );
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pump();
    expect(lastState?['focusedDate'], '2026-05-01T00:00:00.000');
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pump();
    expect(lastState?['focusedDate'], '2026-07-01T00:00:00.000');
  });

  testWidgets('opens event editor on long press', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
      events: [
        CalendarEvent(
          id: 'ev-2',
          title: 'Review',
          start: DateTime(2026, 6, 19, 14),
          end: DateTime(2026, 6, 19, 15),
        ),
      ],
    );
    await tester.longPress(find.text('Review'));
    await tester.pump();
    expect(find.text('Edit event'), findsOneWidget);
  });

  testWidgets('opens create event dialog', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(state: {'focusedDate': '2026-06-19T00:00:00.000'}),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();
    expect(find.text('New event'), findsOneWidget);
  });
}
