import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/utils/color_utils.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

const double _kHourHeight = 48;

enum _CalendarView {
  month,
  week,
  workWeek,
  day,
  threeDay,
  list;

  String get label {
    return switch (this) {
      month => 'Month',
      week => 'Week',
      workWeek => 'Work',
      day => 'Day',
      threeDay => '3 Day',
      list => 'List',
    };
  }
}

class CalendarPanelContent extends StatefulWidget {
  const CalendarPanelContent({
    super.key,
    required this.panel,
    required this.renderContext,
    this.storage,
  });

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;
  final CalendarEventStorage? storage;

  @override
  State<CalendarPanelContent> createState() => _CalendarPanelContentState();
}

class _CalendarPanelContentState extends State<CalendarPanelContent> {
  CalendarEventStorage get _storage => widget.storage ?? const CalendarEventStorage();
  List<CalendarEvent> _events = const [];
  bool _loading = true;
  final ScrollController _scrollController = ScrollController();
  OverlayEntry? _previewEntry;

  _CalendarView get _view {
    final raw = widget.panel.state['view'] as String?;
    return _CalendarView.values.firstWhere(
      (v) => v.name == raw,
      orElse: () => _CalendarView.month,
    );
  }

  DateTime get _focusedDate {
    final raw = widget.panel.state['focusedDate'] as String?;
    return DateTime.tryParse(raw ?? '') ?? DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void didUpdateWidget(covariant CalendarPanelContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.panel.id != widget.panel.id) {
      _loadEvents();
      return;
    }
    final oldState = oldWidget.panel.state;
    final newState = widget.panel.state;
    if (oldState['view'] != newState['view'] ||
        oldState['focusedDate'] != newState['focusedDate'] ||
        oldState['scrollHour'] != newState['scrollHour']) {
      _scheduleScrollOffset();
    }
  }

  @override
  void dispose() {
    _hidePreview();
    _scrollController.dispose();
    super.dispose();
  }

  double get _dayStartHour {
    final raw = widget.panel.state['dayStartHour'];
    if (raw is int) return raw.toDouble();
    if (raw is double) return raw;
    return 8;
  }

  double get _targetScrollHour {
    final raw = widget.panel.state['scrollHour'];
    if (raw is int) return raw.toDouble();
    if (raw is double) return raw;
    return _dayStartHour;
  }

  void _scheduleScrollOffset() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      final hour = _targetScrollHour;
      final offset = (hour * _kHourHeight).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      if ((_scrollController.offset - offset).abs() > 1) {
        _scrollController.jumpTo(offset);
      }
    });
  }

  Future<void> _loadEvents() async {
    setState(() => _loading = true);
    final events = await _storage.loadEvents(widget.panel.id);
    if (mounted) {
      final sorted = List.of(events)..sort((a, b) => a.start.compareTo(b.start));
      setState(() {
        _events = sorted;
        _loading = false;
      });
      _syncEventCount(sorted.length);
      _scheduleScrollOffset();
    }
  }

  void _syncEventCount(int count) {
    final current = widget.panel.state['eventCount'] as int? ?? 0;
    if (current != count) {
      widget.renderContext.onUpdateState({
        ...widget.panel.state,
        'eventCount': count,
      });
    }
  }

  void _setView(_CalendarView view) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'view': view.name,
    });
  }

  void _setFocusedDate(DateTime date) {
    widget.renderContext.onUpdateState({
      ...widget.panel.state,
      'focusedDate': _dateOnly(date).toIso8601String(),
    });
  }

  void _movePeriod(int direction) {
    final current = _focusedDate;
    final next = switch (_view) {
      _CalendarView.month => DateTime(current.year, current.month + direction),
      _CalendarView.week || _CalendarView.workWeek => current.add(Duration(days: 7 * direction)),
      _CalendarView.day => current.add(Duration(days: direction)),
      _CalendarView.threeDay => current.add(Duration(days: 3 * direction)),
      _CalendarView.list => current.add(Duration(days: 7 * direction)),
    };
    _setFocusedDate(next);
  }

  Future<void> _upsertEvent(CalendarEvent event) async {
    final updated = await _storage.upsertEvent(widget.panel.id, event);
    setState(() {
      final list = [..._events.where((e) => e.id != updated.id), updated]
        ..sort((a, b) => a.start.compareTo(b.start));
      _events = list;
    });
    _syncEventCount(_events.length);
  }

  Future<void> _deleteEvent(String eventId) async {
    final ok = await _storage.deleteEvent(widget.panel.id, eventId);
    if (!ok) return;
    setState(() => _events = _events.where((e) => e.id != eventId).toList());
    _syncEventCount(_events.length);
  }

  void _showEventPreview(CalendarEvent event) {
    _hidePreview();
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;
    final panelRect = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final entry = OverlayEntry(
      builder: (ctx) => _EventPreviewOverlay(
        event: event,
        panelRect: panelRect,
        onClose: _hidePreview,
        onEdit: () {
          _hidePreview();
          _showEventDialog(event: event);
        },
      ),
    );
    _previewEntry = entry;
    overlay.insert(entry);
  }

  void _hidePreview() {
    _previewEntry?.remove();
    _previewEntry = null;
  }

  void _showEventDialog({CalendarEvent? event, DateTime? initialDate}) {
    showDialog<_EventDialogResult>(
      context: context,
      builder: (context) => _EventDialog(
        event: event,
        initialDate: initialDate ?? _focusedDate,
      ),
    ).then((result) {
      if (result == null) return;
      if (result.deleted && event != null) {
        _deleteEvent(event.id);
        return;
      }
      if (result.event != null) _upsertEvent(result.event!);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: colors.accentBlue,
        ),
      );
    }

    final focused = _focusedDate;
    final view = _view;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CalendarHeader(
          focusedDate: focused,
          view: view,
          onPrevious: () => _movePeriod(-1),
          onNext: () => _movePeriod(1),
          onToday: () => _setFocusedDate(DateTime.now()),
          onViewChanged: _setView,
          onAddEvent: () => _showEventDialog(initialDate: focused),
        ),
        const Divider(height: 1),
        Expanded(
          child: ScrollableCardMarker(
            child: ScrollableCardRegion(
              child: _CalendarBody(
                view: view,
                focusedDate: focused,
                events: _events,
                scrollController: _scrollController,
                onDayTap: (date) {
                  if (view == _CalendarView.month) {
                    _setFocusedDate(date);
                    _setView(_CalendarView.day);
                    return;
                  }
                  _showEventDialog(initialDate: date);
                },
                onEventTap: _showEventPreview,
                onEventLongPress: (event) => _showEventDialog(event: event),
                onTimeSlotTap: (date) => _showEventDialog(initialDate: date),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CalendarHeader extends StatelessWidget {
  const _CalendarHeader({
    required this.focusedDate,
    required this.view,
    required this.onPrevious,
    required this.onNext,
    required this.onToday,
    required this.onViewChanged,
    required this.onAddEvent,
  });

  final DateTime focusedDate;
  final _CalendarView view;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<_CalendarView> onViewChanged;
  final VoidCallback onAddEvent;

  String get _title {
    final d = focusedDate;
    return switch (view) {
      _CalendarView.month => '${_monthName(d.month)} ${d.year}',
      _CalendarView.week => _weekRangeTitle(_weekStart(d)),
      _CalendarView.workWeek => _weekRangeTitle(_weekStart(d), days: 5),
      _CalendarView.day => '${_monthName(d.month)} ${d.day}, ${d.year}',
      _CalendarView.threeDay => _weekRangeTitle(d, days: 3),
      _CalendarView.list => '${_monthName(d.month)} ${d.year}',
    };
  }

  String _weekRangeTitle(DateTime start, {int days = 7}) {
    final end = start.add(Duration(days: days - 1));
    if (start.year == end.year) {
      return '${_monthName(start.month)} ${start.day} – '
          '${_monthName(end.month)} ${end.day}, ${end.year}';
    }
    return '${_monthName(start.month)} ${start.day}, ${start.year} – '
        '${_monthName(end.month)} ${end.day}, ${end.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            _title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onPrevious,
                icon: Icon(Icons.chevron_left, size: 18, color: colors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                onPressed: onNext,
                icon: Icon(Icons.chevron_right, size: 18, color: colors.textSecondary),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              TextButton(
                onPressed: onToday,
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text('Today', style: TextStyle(fontSize: 12, color: colors.accentBlue)),
              ),
            ],
          ),
          const SizedBox(width: 0, height: 0),
          Wrap(
            spacing: 2,
            runSpacing: 2,
            children: _CalendarView.values.map((v) {
              final selected = v == view;
              return ChoiceChip(
                label: Text(v.label, style: const TextStyle(fontSize: 11)),
                selected: selected,
                onSelected: (_) => onViewChanged(v),
                padding: EdgeInsets.zero,
                labelPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: -2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                selectedColor: colors.accentBlue.withValues(alpha: 0.2),
                backgroundColor: colors.surface,
                side: BorderSide(color: selected ? colors.accentBlue : colors.border),
              );
            }).toList(),
          ),
          IconButton(
            onPressed: onAddEvent,
            icon: Icon(Icons.add, size: 18, color: colors.accentBlue),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ],
      ),
    );
  }
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({
    required this.view,
    required this.focusedDate,
    required this.events,
    required this.scrollController,
    required this.onDayTap,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onTimeSlotTap,
  });

  final _CalendarView view;
  final DateTime focusedDate;
  final List<CalendarEvent> events;
  final ScrollController scrollController;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;
  final ValueChanged<DateTime> onTimeSlotTap;

  @override
  Widget build(BuildContext context) {
    return switch (view) {
      _CalendarView.month => _MonthView(
          focusedDate: focusedDate,
          events: events,
          onDayTap: onDayTap,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
        ),
      _CalendarView.week => _TimelineView(
          startDate: _weekStart(focusedDate),
          dayCount: 7,
          events: events,
          scrollController: scrollController,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
          onTimeSlotTap: onTimeSlotTap,
        ),
      _CalendarView.workWeek => _TimelineView(
          startDate: _weekStart(focusedDate),
          dayCount: 5,
          events: events,
          scrollController: scrollController,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
          onTimeSlotTap: onTimeSlotTap,
        ),
      _CalendarView.day => _TimelineView(
          startDate: focusedDate,
          dayCount: 1,
          events: events,
          scrollController: scrollController,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
          onTimeSlotTap: onTimeSlotTap,
        ),
      _CalendarView.threeDay => _TimelineView(
          startDate: focusedDate,
          dayCount: 3,
          events: events,
          scrollController: scrollController,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
          onTimeSlotTap: onTimeSlotTap,
        ),
      _CalendarView.list => _ListView(
          focusedDate: focusedDate,
          events: events,
          onEventTap: onEventTap,
          onEventLongPress: onEventLongPress,
        ),
    };
  }
}

class _MonthView extends StatelessWidget {
  const _MonthView({
    required this.focusedDate,
    required this.events,
    required this.onDayTap,
    required this.onEventTap,
    required this.onEventLongPress,
  });

  final DateTime focusedDate;
  final List<CalendarEvent> events;
  final ValueChanged<DateTime> onDayTap;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final monthStart = DateTime(focusedDate.year, focusedDate.month);
    final gridStart = monthStart.subtract(
      Duration(days: (monthStart.weekday - DateTime.monday) % 7),
    );
    final today = _dateOnly(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _WeekdayHeader(colors: colors),
        Expanded(
          child: GridView.builder(
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.05,
            ),
            itemCount: 42,
            physics: const NeverScrollableScrollPhysics(),
            itemBuilder: (context, index) {
              final day = gridStart.add(Duration(days: index));
              final inMonth = day.month == focusedDate.month;
              final isToday = _dateOnly(day) == today;
              final dayEvents = events
                  .where((e) => _eventCoversDay(e, day))
                  .toList();
              return _MonthDayCell(
                day: day,
                inMonth: inMonth,
                isToday: isToday,
                events: dayEvents,
                onTap: () => onDayTap(day),
                onEventTap: onEventTap,
                onEventLongPress: onEventLongPress,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _WeekdayHeader extends StatelessWidget {
  const _WeekdayHeader({required this.colors});

  final AppColorScheme colors;

  @override
  Widget build(BuildContext context) {
    final labels = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.border)),
      ),
      child: Row(
        children: labels
            .map(
              (label) => Expanded(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: colors.textMuted, fontWeight: FontWeight.w600),
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _MonthDayCell extends StatelessWidget {
  const _MonthDayCell({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.events,
    required this.onTap,
    required this.onEventTap,
    required this.onEventLongPress,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final List<CalendarEvent> events;
  final VoidCallback onTap;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: inMonth ? colors.surface : colors.surface.withValues(alpha: 0.3),
          border: Border(
            right: BorderSide(color: colors.border.withValues(alpha: 0.5)),
            bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
          ),
        ),
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              alignment: Alignment.center,
              width: 22,
              height: 22,
              decoration: isToday
                  ? BoxDecoration(
                      color: colors.accentBlue,
                      shape: BoxShape.circle,
                    )
                  : null,
              child: Text(
                '${day.day}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isToday
                      ? colors.textPrimary
                      : inMonth
                          ? colors.textPrimary
                          : colors.textMuted,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: events.take(3).map((event) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 1),
                    child: GestureDetector(
                      onTap: () => onEventTap(event),
                      onLongPress: () => onEventLongPress(event),
                      child: _EventChip(event: event, compact: true),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TimelineView extends StatelessWidget {
  const _TimelineView({
    required this.startDate,
    required this.dayCount,
    required this.events,
    required this.scrollController,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onTimeSlotTap,
  });

  final DateTime startDate;
  final int dayCount;
  final List<CalendarEvent> events;
  final ScrollController scrollController;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;
  final ValueChanged<DateTime> onTimeSlotTap;

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      dayCount,
      (i) => _dateOnly(startDate).add(Duration(days: i)),
    );
    return SingleChildScrollView(
      controller: scrollController,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: days.map((day) {
            final dayEvents = events.where((e) => _eventCoversDay(e, day)).toList();
            return Expanded(
              child: _DayColumn(
                day: day,
                events: dayEvents,
                onEventTap: onEventTap,
                onEventLongPress: onEventLongPress,
                onTimeSlotTap: onTimeSlotTap,
                showHeader: dayCount > 1,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.day,
    required this.events,
    required this.onEventTap,
    required this.onEventLongPress,
    required this.onTimeSlotTap,
    required this.showHeader,
  });

  final DateTime day;
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;
  final ValueChanged<DateTime> onTimeSlotTap;
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isToday = _dateOnly(day) == _dateOnly(DateTime.now());
    return Container(
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              color: isToday ? colors.accentBlue.withValues(alpha: 0.1) : null,
              child: Column(
                children: [
                  Text(
                    _weekdayName(day.weekday),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                  Text(
                    '${day.day}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isToday ? colors.accentBlue : colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          if (showHeader) const Divider(height: 1),
          Expanded(
            child: SizedBox(
              height: 24 * _kHourHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: _TimeGridBackground(
                      onTimeTap: (hour) => onTimeSlotTap(
                        day.add(Duration(hours: hour)),
                      ),
                    ),
                  ),
                  ...events.map((event) {
                    return _TimelineEvent(
                      event: event,
                      day: day,
                      onTap: onEventTap,
                      onLongPress: onEventLongPress,
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TimeGridBackground extends StatelessWidget {
  const _TimeGridBackground({required this.onTimeTap});

  final ValueChanged<int> onTimeTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return Column(
      children: List.generate(24, (hour) {
        return InkWell(
          onTap: () => onTimeTap(hour),
          child: Container(
            height: _kHourHeight,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.border.withValues(alpha: 0.3)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [
                Text(
                  '${hour.toString().padLeft(2, '0')}:00',
                  style: TextStyle(fontSize: 9, color: colors.textMuted),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

class _TimelineEvent extends StatelessWidget {
  const _TimelineEvent({
    required this.event,
    required this.day,
    required this.onTap,
    required this.onLongPress,
  });

  final CalendarEvent event;
  final DateTime day;
  final ValueChanged<CalendarEvent> onTap;
  final ValueChanged<CalendarEvent> onLongPress;

  @override
  Widget build(BuildContext context) {
    final start = event.allDay
        ? day
        : (event.start.isBefore(day) ? day : event.start);
    final end = event.allDay
        ? day.add(const Duration(days: 1))
        : (event.effectiveEnd.isAfter(day.add(const Duration(days: 1)))
            ? day.add(const Duration(days: 1))
            : event.effectiveEnd);

    final startMinutes = start.difference(day).inMinutes;
    final durationMinutes = math.max(30, end.difference(start).inMinutes);
    final top = (startMinutes / 60.0) * _kHourHeight;
    final height = (durationMinutes / 60.0) * _kHourHeight;

    return Positioned(
      top: top,
      left: 4,
      right: 4,
      height: height,
      child: GestureDetector(
        onTap: () => onTap(event),
        onLongPress: () => onLongPress(event),
        child: _EventChip(event: event),
      ),
    );
  }
}

class _ListView extends StatelessWidget {
  const _ListView({
    required this.focusedDate,
    required this.events,
    required this.onEventTap,
    required this.onEventLongPress,
  });

  final DateTime focusedDate;
  final List<CalendarEvent> events;
  final ValueChanged<CalendarEvent> onEventTap;
  final ValueChanged<CalendarEvent> onEventLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final futureEvents = events
        .where((e) => e.start.isAfter(focusedDate.subtract(const Duration(days: 1))))
        .toList();
    if (futureEvents.isEmpty) {
      return Center(
        child: Text(
          'No upcoming events',
          style: TextStyle(color: colors.textMuted),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: futureEvents.length,
      itemBuilder: (context, index) {
        final event = futureEvents[index];
        return InkWell(
          onTap: () => onEventTap(event),
          onLongPress: () => onEventLongPress(event),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              color: colors.surface,
              border: Border.all(color: colors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: event.color == null
                        ? colors.accentBlue
                        : Color(event.color!),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        event.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatEventTime(event),
                        style: TextStyle(fontSize: 11, color: colors.textSecondary),
                      ),
                      if (event.description.isNotEmpty)
                        Text(
                          event.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: colors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip({required this.event, this.compact = false});

  final CalendarEvent event;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final baseColor = event.color == null ? colors.accentBlue : Color(event.color!);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: baseColor.withValues(alpha: 0.4)),
      ),
      child: Text(
        event.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: compact ? 9 : 10,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
    );
  }
}

class _EventDialogResult {
  const _EventDialogResult({this.event, this.deleted = false});

  final CalendarEvent? event;
  final bool deleted;
}

class _EventDialog extends StatefulWidget {
  const _EventDialog({this.event, required this.initialDate});

  final CalendarEvent? event;
  final DateTime initialDate;

  @override
  State<_EventDialog> createState() => _EventDialogState();
}

class _EventDialogState extends State<_EventDialog> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;
  late final TextEditingController _colorCtrl;
  late final TextEditingController _urlCtrl;
  late bool _allDay;
  late DateTime _start;
  DateTime? _end;

  @override
  void initState() {
    super.initState();
    final event = widget.event;
    _titleCtrl = TextEditingController(text: event?.title ?? '');
    _descCtrl = TextEditingController(text: event?.description ?? '');
    _colorCtrl = TextEditingController(
      text: event?.color == null ? '' : _colorToHex(Color(event!.color!)),
    );
    _urlCtrl = TextEditingController(text: event?.meetingUrl ?? '');
    _allDay = event?.allDay ?? false;
    _start = event?.start ?? widget.initialDate;
    _end = event?.end;
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _colorCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final current = isStart ? _start : (_end ?? _start);
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = DateTime(picked.year, picked.month, picked.day, _start.hour, _start.minute);
      } else {
        _end = DateTime(picked.year, picked.month, picked.day, current.hour, current.minute);
      }
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final current = isStart ? _start : (_end ?? _start);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _start = DateTime(_start.year, _start.month, _start.day, picked.hour, picked.minute);
      } else {
        final base = _end ?? _start;
        _end = DateTime(base.year, base.month, base.day, picked.hour, picked.minute);
      }
    });
  }

  CalendarEvent? _buildEvent() {
    final title = _titleCtrl.text.trim();
    if (title.isEmpty) return null;
    final color = parseColor(_colorCtrl.text.trim());
    final id = widget.event?.id ?? DateTime.now().millisecondsSinceEpoch.toString();
    return CalendarEvent(
      id: id,
      title: title,
      start: _start,
      end: _end,
      allDay: _allDay,
      description: _descCtrl.text.trim(),
      color: color?.toARGB32(),
      meetingUrl: _urlCtrl.text.trim().isEmpty ? null : _urlCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        widget.event == null ? 'New event' : 'Edit event',
        style: TextStyle(color: colors.textPrimary),
      ),
      content: SingleChildScrollView(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _titleCtrl,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Title',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _allDay,
                    onChanged: (value) => setState(() => _allDay = value ?? false),
                    activeColor: colors.accentBlue,
                  ),
                  Text('All day', style: TextStyle(color: colors.textPrimary)),
                ],
              ),
              const SizedBox(height: 8),
              _DateTimeRow(
                label: 'Start',
                dateTime: _start,
                onDate: () => _pickDate(isStart: true),
                onTime: _allDay ? null : () => _pickTime(isStart: true),
              ),
              const SizedBox(height: 8),
              _DateTimeRow(
                label: 'End',
                dateTime: _end,
                onDate: () => _pickDate(isStart: false),
                onTime: _allDay ? null : () => _pickTime(isStart: false),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descCtrl,
                style: TextStyle(color: colors.textPrimary),
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Description',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _colorCtrl,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Color (#RRGGBB, optional)',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _urlCtrl,
                style: TextStyle(color: colors.textPrimary),
                decoration: InputDecoration(
                  labelText: 'Meeting link (optional)',
                  labelStyle: TextStyle(color: colors.textSecondary),
                  border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        if (widget.event != null)
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(const _EventDialogResult(deleted: true));
            },
            child: Text('Delete', style: TextStyle(color: colors.accentRed)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
        ),
        FilledButton(
          onPressed: () {
            final event = _buildEvent();
            if (event != null) {
              Navigator.of(context).pop(_EventDialogResult(event: event));
            }
          },
          style: FilledButton.styleFrom(backgroundColor: colors.accentBlue),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _EventPreviewOverlay extends StatelessWidget {
  const _EventPreviewOverlay({
    required this.event,
    required this.panelRect,
    required this.onClose,
    required this.onEdit,
  });

  final CalendarEvent event;
  final Rect panelRect;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final size = MediaQuery.sizeOf(context);
    const cardWidth = 260.0;
    const cardHeight = 180.0;
    final left = (panelRect.center.dx - cardWidth / 2).clamp(8.0, size.width - cardWidth - 8);
    final top = (panelRect.center.dy - cardHeight / 2).clamp(8.0, size.height - cardHeight - 8);

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onClose,
            child: Container(color: Colors.transparent),
          ),
        ),
        Positioned(
          left: left,
          top: top,
          width: cardWidth,
          child: Material(
            color: colors.surface,
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: event.color == null ? colors.accentBlue : Color(event.color!),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          event.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: onEdit,
                        icon: Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        splashRadius: 12,
                      ),
                      IconButton(
                        onPressed: onClose,
                        icon: Icon(Icons.close, size: 16, color: colors.textSecondary),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                        splashRadius: 12,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _formatEventTime(event),
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                  if (event.description.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      event.description,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ],
                  if (event.meetingUrl?.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () {},
                      child: Row(
                        children: [
                          Icon(Icons.videocam_outlined, size: 14, color: colors.accentBlue),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              event.meetingUrl!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: colors.accentBlue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DateTimeRow extends StatelessWidget {
  const _DateTimeRow({
    required this.label,
    required this.dateTime,
    required this.onDate,
    this.onTime,
  });

  final String label;
  final DateTime? dateTime;
  final VoidCallback onDate;
  final VoidCallback? onTime;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final dt = dateTime;
    return Row(
      children: [
        SizedBox(width: 50, child: Text(label, style: TextStyle(color: colors.textMuted, fontSize: 12))),
        TextButton(
          onPressed: onDate,
          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
          child: Text(
            dt == null ? '—' : '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}',
            style: TextStyle(color: colors.textPrimary, fontSize: 12),
          ),
        ),
        if (onTime != null && dt != null)
          TextButton(
            onPressed: onTime,
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: Text(
              '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
              style: TextStyle(color: colors.textPrimary, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

DateTime _dateOnly(DateTime date) {
  return DateTime(date.year, date.month, date.day);
}

DateTime _weekStart(DateTime date) {
  final d = _dateOnly(date);
  return d.subtract(Duration(days: (d.weekday - DateTime.monday) % 7));
}

bool _eventCoversDay(CalendarEvent event, DateTime day) {
  final startDay = _dateOnly(event.start);
  final endDay = event.end == null ? startDay : _dateOnly(event.effectiveEnd);
  final target = _dateOnly(day);
  return !target.isBefore(startDay) && !target.isAfter(endDay);
}

String _monthName(int month) {
  const names = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return names[month - 1];
}

String _weekdayName(int weekday) {
  const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return names[weekday - 1];
}

String _formatEventTime(CalendarEvent event) {
  if (event.allDay) return 'All day';
  final start = '${event.start.hour.toString().padLeft(2, '0')}:${event.start.minute.toString().padLeft(2, '0')}';
  final end = event.end == null
      ? null
      : '${event.end!.hour.toString().padLeft(2, '0')}:${event.end!.minute.toString().padLeft(2, '0')}';
  return end == null ? start : '$start – $end';
}

String _colorToHex(Color color) {
  final value = color.toARGB32();
  return '#${(value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}
