// covers-write: board.calendar
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/calendar_handler.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late CalendarCliHandler handler;

  setUp(() {
    tmpDir = Directory.systemTemp.createTempSync('calendar_handler_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tmpDir.path));
    handler = const CalendarCliHandler();
  });

  tearDown(() {
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  BoardPanelInstance newPanel({Map<String, dynamic> state = const {}}) =>
      BoardPanelInstance(
        id: 'test-panel-calendar',
        type: 'board.calendar',
        title: 'Calendar',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
        state: state,
      );

  group('CalendarCliHandler — metadata', () {
    test('typeId is board.calendar', () {
      expect(handler.typeId, 'board.calendar');
    });

    test('supportedActions includes all actions', () {
      expect(
        handler.supportedActions,
        containsAll([
          'events',
          'create-event',
          'add-event',
          'update-event',
          'delete-event',
          'set-view',
          'focus-date',
          'scroll-to-time',
          'scroll-to-event',
          'show-event',
        ]),
      );
    });

    test('getContent returns view, focusedDate and eventCount', () {
      final panel = newPanel(
        state: {
          'view': 'week',
          'focusedDate': '2026-06-19T00:00:00.000',
          'eventCount': 5,
        },
      );
      final content = handler.getContent(panel);
      expect(content['view'], 'week');
      expect(content['focusedDate'], '2026-06-19T00:00:00.000');
      expect(content['eventCount'], 5);
    });
  });

  group('CalendarCliHandler — events action', () {
    test('events returns empty list when no events', () async {
      final panel = newPanel();
      final r = await handler.handleAction('events', {}, panel);
      expect(r.ok, isTrue);
      expect(r.data!['count'], 0);
      expect(r.data!['events'], isEmpty);
    });

    test('events filters by date range', () async {
      final panel = newPanel(state: {'view': 'day', 'focusedDate': '2026-06-19'});
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-1',
          title: 'Today',
          start: DateTime(2026, 6, 19, 10),
          end: DateTime(2026, 6, 19, 11),
        ),
      );
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-2',
          title: 'Tomorrow',
          start: DateTime(2026, 6, 20, 10),
          end: DateTime(2026, 6, 20, 11),
        ),
      );
      final r = await handler.handleAction('events', {}, panel);
      expect(r.data!['count'], 1);
      expect(
        ((r.data!['events'] as List).first as Map<String, dynamic>)['title'],
        'Today',
      );
    });
  });

  group('CalendarCliHandler — create-event action', () {
    test('create-event requires title', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'create-event',
        {'start': '2026-06-19T10:00:00'},
        panel,
      );
      expect(r.ok, isFalse);
      expect(r.message, contains('title'));
    });

    test('create-event requires start', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'create-event',
        {'title': 'Standup'},
        panel,
      );
      expect(r.ok, isFalse);
      expect(r.message, contains('start'));
    });

    test('create-event adds event and updates count', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'create-event',
        {
          'title': 'Standup',
          'start': '2026-06-19T10:00:00',
          'end': '2026-06-19T11:00:00',
          'allDay': 'false',
          'description': 'Daily sync',
          'color': '#3B82F6',
        },
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.message, contains('Standup'));
      expect(r.stateUpdate!['eventCount'], 1);
      expect((r.data!['event'] as Map<String, dynamic>)['title'], 'Standup');
    });
  });

  group('CalendarCliHandler — update-event action', () {
    test('update-event requires eventId', () async {
      final panel = newPanel();
      final r = await handler.handleAction('update-event', {}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('eventId'));
    });

    test('update-event updates existing event', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-1',
          title: 'Old',
          start: DateTime(2026, 6, 19, 10),
        ),
      );
      final r = await handler.handleAction(
        'update-event',
        {'eventId': 'ev-1', 'title': 'New'},
        panel,
      );
      expect(r.ok, isTrue);
      expect((r.data!['event'] as Map<String, dynamic>)['title'], 'New');
    });

    test('update-event finds event by title', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-1',
          title: 'Standup',
          start: DateTime(2026, 6, 19, 10),
        ),
      );
      final r = await handler.handleAction(
        'update-event',
        {'eventId': 'Standup', 'description': 'Daily'},
        panel,
      );
      expect(r.ok, isTrue);
      expect((r.data!['event'] as Map<String, dynamic>)['description'], 'Daily');
    });

    test('update-event returns ok=false when event missing', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'update-event',
        {'eventId': 'missing'},
        panel,
      );
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — delete-event action', () {
    test('delete-event requires eventId', () async {
      final panel = newPanel();
      final r = await handler.handleAction('delete-event', {}, panel);
      expect(r.ok, isFalse);
      expect(r.message, contains('eventId'));
    });

    test('delete-event removes event', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-1',
          title: 'To delete',
          start: DateTime(2026, 6, 19, 10),
        ),
      );
      final r = await handler.handleAction(
        'delete-event',
        {'eventId': 'ev-1'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['eventCount'], 0);
    });

    test('delete-event finds event by title', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-1',
          title: 'Retrospective',
          start: DateTime(2026, 6, 19, 10),
        ),
      );
      final r = await handler.handleAction(
        'delete-event',
        {'eventId': 'Retrospective'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['eventCount'], 0);
    });

    test('delete-event returns ok=false when event missing', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'delete-event',
        {'eventId': 'missing'},
        panel,
      );
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — set-view action', () {
    test('set-view updates state', () async {
      final panel = newPanel(state: {'view': 'month'});
      final r = await handler.handleAction(
        'set-view',
        {'view': 'week'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['view'], 'week');
    });

    test('set-view rejects invalid view', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'set-view',
        {'view': 'year'},
        panel,
      );
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — focus-date action', () {
    test('focus-date sets focusedDate', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'focus-date',
        {'date': '2026-06-21'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['focusedDate'], '2026-06-21T00:00:00.000');
    });

    test('focus-date rejects invalid date', () async {
      final panel = newPanel();
      final r = await handler.handleAction('focus-date', {'date': 'bad'}, panel);
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — scroll-to-time action', () {
    test('scroll-to-time sets scrollHour', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'scroll-to-time',
        {'hour': '14'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['scrollHour'], 14);
    });

    test('scroll-to-time clamps invalid hour', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'scroll-to-time',
        {'hour': '30'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['scrollHour'], 23);
    });
  });

  group('CalendarCliHandler — scroll-to-event action', () {
    test('scroll-to-event focuses event day and hour', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-scroll',
          title: 'Scroll target',
          start: DateTime(2026, 6, 21, 14, 30),
        ),
      );
      final r = await handler.handleAction(
        'scroll-to-event',
        {'eventId': 'ev-scroll'},
        panel,
      );
      expect(r.ok, isTrue);
      expect(r.stateUpdate!['view'], 'day');
      expect(r.stateUpdate!['focusedDate'], '2026-06-21T00:00:00.000');
      expect(r.stateUpdate!['scrollHour'], 14);
    });

    test('scroll-to-event returns ok=false when event missing', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'scroll-to-event',
        {'eventId': 'missing'},
        panel,
      );
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — show-event action', () {
    test('show-event returns event details', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-show',
          title: 'Show me',
          start: DateTime(2026, 6, 21, 10),
          description: 'Details',
        ),
      );
      final r = await handler.handleAction(
        'show-event',
        {'eventId': 'ev-show'},
        panel,
      );
      expect(r.ok, isTrue);
      final data = r.data!['event'] as Map<String, dynamic>;
      expect(data['title'], 'Show me');
      expect(data['description'], 'Details');
    });

    test('show-event finds event by title', () async {
      final panel = newPanel();
      const storage = CalendarEventStorage();
      await storage.upsertEvent(
        panel.id,
        CalendarEvent(
          id: 'ev-show',
          title: 'Find me',
          start: DateTime(2026, 6, 21, 10),
          description: 'Details',
        ),
      );
      final r = await handler.handleAction(
        'show-event',
        {'eventId': 'Find me'},
        panel,
      );
      expect(r.ok, isTrue);
      final data = r.data!['event'] as Map<String, dynamic>;
      expect(data['title'], 'Find me');
    });

    test('show-event returns ok=false when event missing', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'show-event',
        {'eventId': 'missing'},
        panel,
      );
      expect(r.ok, isFalse);
    });
  });

  group('CalendarCliHandler — date ranges', () {
    test('month view range covers whole month', () async {
      final panel = newPanel(
        state: {'view': 'month', 'focusedDate': '2026-02-15T00:00:00'},
      );
      final r = await handler.handleAction('events', {}, panel);
      final start = DateTime.parse(r.data!['start'] as String);
      final end = DateTime.parse(r.data!['end'] as String);
      expect(start, DateTime(2026, 2));
      expect(end.year, 2026);
      expect(end.month, 2);
      expect(end.day, 28);
    });

    test('explicit range overrides default', () async {
      final panel = newPanel();
      final r = await handler.handleAction(
        'events',
        {
          'start': '2026-06-01T00:00:00',
          'end': '2026-06-02T00:00:00',
        },
        panel,
      );
      expect(r.data!['start'], '2026-06-01T00:00:00.000');
      expect(r.data!['end'], '2026-06-02T00:00:00.000');
    });
  });
}
