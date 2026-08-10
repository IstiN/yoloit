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

class _CountingStorage extends CalendarEventStorage {
  int loads = 0;

  @override
  Future<List<CalendarEvent>> loadEvents(String panelId) async {
    loads++;
    return const [];
  }

  @override
  Future<CalendarEvent> upsertEvent(String panelId, CalendarEvent event) async =>
      event;

  @override
  Future<bool> deleteEvent(String panelId, String eventId) async => true;
}

/// Host that lets a test swap the panel instance, triggering
/// [CalendarPanelContent.didUpdateWidget] on the same [State].
class _CalendarHost extends StatefulWidget {
  const _CalendarHost({
    super.key,
    required this.panel,
    required this.renderContext,
    required this.storage,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  final CalendarEventStorage storage;

  @override
  State<_CalendarHost> createState() => _CalendarHostState();
}

class _CalendarHostState extends State<_CalendarHost> {
  late BoardPanelInstance _panel = widget.panel;

  void updatePanel(BoardPanelInstance next) => setState(() => _panel = next);

  @override
  Widget build(BuildContext context) {
    return CalendarPanelContent(
      panel: _panel,
      renderContext: widget.renderContext,
      storage: widget.storage,
    );
  }
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

  group('didUpdateWidget', () {
    Future<GlobalKey<_CalendarHostState>> pumpHost(
      WidgetTester tester,
      BoardPanelInstance panel, {
      CalendarEventStorage? storage,
    }) async {
      final key = GlobalKey<_CalendarHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _CalendarHost(
              key: key,
              panel: panel,
              renderContext: renderContext,
              storage: storage ?? const _FakeStorage([]),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      return key;
    }

    double scrollOffset(WidgetTester tester) {
      return tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .pixels;
    }

    testWidgets('reschedules scroll offset when scrollHour changes', (
      tester,
    ) async {
      final key = await pumpHost(
        tester,
        newPanel(
          state: {
            'view': 'week',
            'focusedDate': '2026-06-15T00:00:00.000',
            'scrollHour': 10,
          },
        ),
      );
      // Initial load applied scrollHour 10 (10 * 48px).
      expect(scrollOffset(tester), moreOrLessEquals(480, epsilon: 1));

      key.currentState!.updatePanel(
        newPanel(
          state: {
            'view': 'week',
            'focusedDate': '2026-06-15T00:00:00.000',
            'scrollHour': 2,
          },
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(scrollOffset(tester), moreOrLessEquals(96, epsilon: 1));
    });

    testWidgets('reloads events when the panel id changes', (tester) async {
      final storage = _CountingStorage();
      final key = await pumpHost(
        tester,
        newPanel(state: {'focusedDate': '2026-06-15T00:00:00.000'}),
        storage: storage,
      );
      expect(storage.loads, 1);

      // Same id, unrelated state: no reload.
      key.currentState!.updatePanel(
        newPanel(
          state: {'focusedDate': '2026-06-15T00:00:00.000', 'view': 'week'},
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(storage.loads, 1);

      // Different id triggers a reload.
      key.currentState!.updatePanel(
        const BoardPanelInstance(
          id: 'cal-widget-2',
          type: 'board.calendar',
          title: 'Calendar',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          state: {'focusedDate': '2026-06-15T00:00:00.000'},
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(storage.loads, 2);
    });
  });

  testWidgets('list view formats event times', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(
        state: {
          'view': 'list',
          'focusedDate': '2026-06-01T00:00:00.000',
        },
      ),
      events: [
        CalendarEvent(
          id: 'ev-all-day',
          title: 'Offsite',
          start: DateTime(2026, 6, 2),
          allDay: true,
        ),
        CalendarEvent(
          id: 'ev-ranged',
          title: 'Standup',
          start: DateTime(2026, 6, 2, 10),
          end: DateTime(2026, 6, 2, 11),
        ),
        CalendarEvent(
          id: 'ev-open',
          title: 'Gym',
          start: DateTime(2026, 6, 2, 9, 30),
        ),
      ],
    );

    expect(find.text('All day'), findsOneWidget);
    expect(find.text('10:00 – 11:00'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
  });

  testWidgets('event dialog picks start/end dates and times', (tester) async {
    await pumpCalendar(
      tester,
      newPanel(state: {'focusedDate': '2026-06-19T09:15:00.000'}),
    );
    await tester.tap(find.byIcon(Icons.add));
    await tester.pumpAndSettle();
    expect(find.text('New event'), findsOneWidget);

    // Start date: cancelling the picker keeps the current value...
    await tester.tap(find.text('2026-06-19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    // ...accepting it applies the picked date.
    await tester.tap(find.text('2026-06-19'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    // Start time: cancel first, then accept the initial time.
    await tester.tap(find.text('09:15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('09:15'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    // End date: accepting the picker fills the end row and reveals its time.
    await tester.tap(find.text('—'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();
    // End time (second '09:15' is the end row).
    await tester.tap(find.text('09:15').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK').last);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Planning');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Planning'), findsOneWidget);
  });
}
