import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

/// CLI handler for Calendar panels (`board.calendar`).
///
/// Supported actions:
/// - `events` — list events in a date range
/// - `create-event` / `add-event` — add a new event
/// - `update-event` — edit an existing event
/// - `delete-event` — remove an event
/// - `set-view` — switch calendar view
class CalendarCliHandler extends PanelCliHandler {
  const CalendarCliHandler();

  final CalendarEventStorage _storage = const CalendarEventStorage();

  @override
  String get typeId => 'board.calendar';

  @override
  List<String> get supportedActions => [
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
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'view': panel.state['view'] ?? 'month',
      'focusedDate': panel.state['focusedDate'],
      'eventCount': panel.state['eventCount'] ?? 0,
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'events':
        return _handleEvents(args, panel);
      case 'create-event':
      case 'add-event':
        return _handleCreateEvent(args, panel);
      case 'update-event':
        return _handleUpdateEvent(args, panel);
      case 'delete-event':
        return _handleDeleteEvent(args, panel);
      case 'set-view':
        return _handleSetView(args, panel);
      case 'focus-date':
        return _handleFocusDate(args, panel);
      case 'scroll-to-time':
        return _handleScrollToTime(args, panel);
      case 'scroll-to-event':
        return _handleScrollToEvent(args, panel);
      case 'show-event':
        return _handleShowEvent(args, panel);
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  Future<CliActionResult> _handleEvents(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final range = _dateRange(args, panel);
    final events = await _storage.loadEvents(panel.id);
    final filtered = events.where((event) {
      final start = event.start;
      final end = event.effectiveEnd;
      return !end.isBefore(range.start) && !start.isAfter(range.end);
    }).toList();
    return CliActionResult(
      data: {
        'start': range.start.toIso8601String(),
        'end': range.end.toIso8601String(),
        'count': filtered.length,
        'events': filtered.map(_eventToJson).toList(),
      },
    );
  }

  Future<CliActionResult> _handleCreateEvent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final title = _string(args['title']);
    if (title == null || title.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: title',
      );
    }
    final start = _parseDateTime(args['start']);
    if (start == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing or invalid field: start',
      );
    }
    final event = CalendarEvent(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      title: title,
      start: start,
      end: _parseDateTime(args['end']),
      allDay: args['allDay'] == true || (args['allDay']?.toString().toLowerCase() == 'true'),
      description: _string(args['description']) ?? '',
      color: _parseColor(args['color']),
      meetingUrl: _string(args['meetingUrl'] ?? args['url']),
    );
    await _storage.upsertEvent(panel.id, event);
    final count = await _storage.countEvents(panel.id);
    return CliActionResult(
      message: 'Created event: ${event.title}',
      data: {'event': _eventToJson(event)},
      stateUpdate: {'eventCount': count},
    );
  }

  Future<CliActionResult> _handleUpdateEvent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final eventId = _requireEventId(args);
    if (eventId.result != null) return eventId.result!;
    final events = await _storage.loadEvents(panel.id);
    final existing = _findEventByIdOrTitle(events, eventId.value!);
    if (existing == null) {
      return CliActionResult(
        ok: false,
        message: 'Event not found: ${eventId.value}',
      );
    }
    final updated = existing.copyWith(
      title: _string(args['title']),
      start: _parseDateTime(args['start']),
      end: _parseDateTime(args['end']),
      allDay: _boolOrNull(args['allDay']),
      description: _string(args['description']),
      color: _parseColor(args['color']),
      meetingUrl: _string(args['meetingUrl'] ?? args['url']),
    );
    await _storage.upsertEvent(panel.id, updated);
    final count = await _storage.countEvents(panel.id);
    return CliActionResult(
      message: 'Updated event: ${updated.title}',
      data: {'event': _eventToJson(updated)},
      stateUpdate: {'eventCount': count},
    );
  }

  Future<CliActionResult> _handleDeleteEvent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final eventId = _requireEventId(args);
    if (eventId.result != null) return eventId.result!;
    final events = await _storage.loadEvents(panel.id);
    final existing = _findEventByIdOrTitle(events, eventId.value!);
    if (existing == null) {
      return CliActionResult(
        ok: false,
        message: 'Event not found: ${eventId.value}',
      );
    }
    final ok = await _storage.deleteEvent(panel.id, existing.id);
    final count = await _storage.countEvents(panel.id);
    return CliActionResult(
      message: 'Deleted event: ${existing.title}',
      stateUpdate: {'eventCount': count},
    );
  }

  ({String? value, CliActionResult? result}) _requireEventId(
    Map<String, dynamic> args,
  ) {
    final eventId = _string(args['eventId'] ?? args['id']);
    if (eventId == null || eventId.isEmpty) {
      return (
        value: null,
        result: const CliActionResult(
          ok: false,
          message: 'Missing required field: eventId',
        ),
      );
    }
    return (value: eventId, result: null);
  }

  CalendarEvent? _findEventByIdOrTitle(
    List<CalendarEvent> events,
    String idOrTitle,
  ) {
    final needle = idOrTitle.toLowerCase();
    CalendarEvent? partialMatch;
    for (final event in events) {
      if (event.id == idOrTitle) return event;
      final title = event.title.toLowerCase();
      if (title == needle) return event;
      if (partialMatch == null && title.contains(needle)) {
        partialMatch = event;
      }
    }
    return partialMatch;
  }

  CliActionResult _handleSetView(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final view = _string(args['view']);
    const allowed = {'month', 'week', 'workWeek', 'day', 'threeDay', 'list'};
    if (view == null || !allowed.contains(view)) {
      return CliActionResult(
        ok: false,
        message: 'Invalid view. Allowed: ${allowed.join(', ')}',
      );
    }
    return CliActionResult(
      message: 'View set to $view',
      stateUpdate: {
        ...panel.state,
        'view': view,
      },
    );
  }

  CliActionResult _handleFocusDate(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final date = _parseDateTime(args['date'] ?? args['focusedDate']);
    if (date == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing or invalid field: date',
      );
    }
    return CliActionResult(
      message: 'Focused date set to ${_dateOnly(date).toIso8601String()}',
      stateUpdate: {
        ...panel.state,
        'focusedDate': _dateOnly(date).toIso8601String(),
      },
    );
  }

  CliActionResult _handleScrollToTime(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final hour = _parseHour(args['hour'] ?? args['time']);
    if (hour == null) {
      return const CliActionResult(
        ok: false,
        message: 'Missing or invalid field: hour (0-23)',
      );
    }
    return CliActionResult(
      message: 'Scrolled to ${hour.toString().padLeft(2, '0')}:00',
      stateUpdate: {
        ...panel.state,
        'scrollHour': hour,
      },
    );
  }

  Future<CliActionResult> _handleScrollToEvent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final eventId = _string(args['eventId'] ?? args['id']);
    final titleQuery = _string(args['title']);
    final events = await _storage.loadEvents(panel.id);
    final event = events.firstWhereOrNull((e) {
      if (eventId != null && e.id == eventId) return true;
      if (titleQuery != null &&
          e.title.toLowerCase().contains(titleQuery.toLowerCase())) {
        return true;
      }
      return false;
    });
    if (event == null) {
      return const CliActionResult(
        ok: false,
        message: 'Event not found',
      );
    }
    return CliActionResult(
      message: 'Focused event: ${event.title}',
      data: {'event': _eventToJson(event)},
      stateUpdate: {
        ...panel.state,
        'focusedDate': _dateOnly(event.start).toIso8601String(),
        'scrollHour': event.start.hour.toDouble(),
        'view': 'day',
      },
    );
  }

  Future<CliActionResult> _handleShowEvent(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    final eventId = _string(args['eventId'] ?? args['id']);
    if (eventId == null || eventId.isEmpty) {
      return const CliActionResult(
        ok: false,
        message: 'Missing required field: eventId',
      );
    }
    final events = await _storage.loadEvents(panel.id);
    final event = _findEventByIdOrTitle(events, eventId);
    if (event == null) {
      return CliActionResult(
        ok: false,
        message: 'Event not found: $eventId',
      );
    }
    return CliActionResult(
      message: event.title,
      data: {'event': _eventToJson(event)},
    );
  }

  int? _parseHour(dynamic value) {
    if (value is int) return value.clamp(0, 23);
    if (value is double) return value.toInt().clamp(0, 23);
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed.clamp(0, 23);
      final dt = DateTime.tryParse('1970-01-01T$value');
      if (dt != null) return dt.hour;
    }
    return null;
  }

  DateTime _dateOnly(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  ({DateTime start, DateTime end}) _dateRange(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final focused = _parseDateTime(panel.state['focusedDate']) ?? DateTime.now();
    final explicitStart = _parseDateTime(args['start'] ?? args['from']);
    final explicitEnd = _parseDateTime(args['end'] ?? args['to']);
    if (explicitStart != null && explicitEnd != null) {
      return (start: explicitStart, end: explicitEnd);
    }
    final view = panel.state['view'] as String? ?? 'month';
    final startDay = DateTime(focused.year, focused.month, focused.day);
    switch (view) {
      case 'week':
      case 'workWeek':
        final weekStart = startDay.subtract(
          Duration(days: (startDay.weekday - DateTime.monday) % 7),
        );
        return (
          start: weekStart,
          end: weekStart.add(const Duration(days: 7, microseconds: -1)),
        );
      case 'day':
        return (
          start: startDay,
          end: startDay.add(const Duration(days: 1, microseconds: -1)),
        );
      case 'threeDay':
        return (
          start: startDay,
          end: startDay.add(const Duration(days: 3, microseconds: -1)),
        );
      case 'list':
        return (
          start: startDay,
          end: startDay.add(const Duration(days: 30)),
        );
      case 'month':
      default:
        final monthStart = DateTime(focused.year, focused.month);
        final monthEnd = DateTime(focused.year, focused.month + 1)
            .subtract(const Duration(microseconds: 1));
        return (start: monthStart, end: monthEnd);
    }
  }

  Map<String, dynamic> _eventToJson(CalendarEvent event) {
    return <String, dynamic>{
      'id': event.id,
      'title': event.title,
      'start': event.start.toIso8601String(),
      if (event.end != null) 'end': event.end!.toIso8601String(),
      'allDay': event.allDay,
      'description': event.description,
      if (event.color != null) 'color': event.color,
      if (event.meetingUrl != null && event.meetingUrl!.isNotEmpty)
        'meetingUrl': event.meetingUrl,
    };
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  int? _parseColor(dynamic value) {
    if (value == null) return null;
    final color = parseColor(value.toString());
    return color?.toARGB32();
  }

  bool? _boolOrNull(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final lower = value.toString().toLowerCase();
    if (lower == 'true' || lower == '1' || lower == 'yes') return true;
    if (lower == 'false' || lower == '0' || lower == 'no') return false;
    return null;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'events': const CliActionHelp(
      description: 'List events in a date range',
      params: {
        'start': 'Start date/time (ISO8601, optional)',
        'end': 'End date/time (ISO8601, optional)',
      },
    ),
    'create-event': const CliActionHelp(
      description: 'Create a new calendar event',
      params: {
        'title': 'Event title',
        'start': 'Start date/time (ISO8601)',
        'end': 'End date/time (ISO8601, optional)',
        'allDay': 'true/false',
        'description': 'Optional description',
        'color': 'Optional color (#RRGGBB)',
      },
    ),
    'update-event': const CliActionHelp(
      description: 'Update an existing event by id or title',
      params: {
        'eventId': 'Event id or title',
        'title': 'New title',
        'start': 'New start',
        'end': 'New end',
        'allDay': 'true/false',
        'description': 'New description',
        'color': 'New color (#RRGGBB)',
      },
    ),
    'delete-event': const CliActionHelp(
      description: 'Delete an event by id or title',
      params: {'eventId': 'Event id or title'},
    ),
    'set-view': const CliActionHelp(
      description: 'Switch calendar view',
      params: {'view': 'month | week | workWeek | day | threeDay | list'},
    ),
    'focus-date': const CliActionHelp(
      description: 'Set the focused calendar date',
      params: {'date': 'Date (ISO8601)'},
    ),
    'scroll-to-time': const CliActionHelp(
      description: 'Scroll the day/week timeline to an hour',
      params: {'hour': 'Hour 0-23, e.g. 9 or 14'},
    ),
    'scroll-to-event': const CliActionHelp(
      description: 'Focus and scroll to an event',
      params: {
        'eventId': 'Event id (optional if title given)',
        'title': 'Event title substring (optional)',
      },
    ),
    'show-event': const CliActionHelp(
      description: 'Show details of a single event by id or title',
      params: {'eventId': 'Event id or title'},
    ),
  };
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
