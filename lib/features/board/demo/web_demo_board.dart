import 'package:flutter/material.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/plugin_type_ids.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';
import 'package:yoloit/features/table/model/table_models.dart';

/// Seeds a default web demo board with interactive panels that work in the
/// browser via [FileStorageAdapter] / SharedPreferences.
///
/// This is intentionally separate from desktop board defaults so the web demo
/// can showcase markdown notes, sticky notes, shapes, kanban, checklists,
/// timers, calendars, tables, charts, and webpages without native-only plugins.
class WebDemoBoardBuilder {
  const WebDemoBoardBuilder._();

  /// Creates a pre-populated demo board and inserts it into [cubit].
  ///
  /// Returns the created board id.
  static Future<String> build(BoardCubit cubit) async {
    final board = await cubit.createBoard(name: 'YoLoIT Web Demo');
    if (board == null) {
      throw StateError('Could not create demo board');
    }

    final panels = _buildPanels();
    for (final panel in panels) {
      await cubit.addPanel(panel, boardId: board.id);
    }

    await _seedCalendarEvents(panels);

    return board.id;
  }

  static List<BoardPanelInstance> _buildPanels() {
    var x = 120.0;
    var y = 120.0;
    const gap = 40.0;

    BoardPanelInstance place(
      String type,
      String title,
      Size size,
      Map<String, dynamic> state,
    ) {
      final panel = BoardPanelInstance(
        id: 'panel-${type.replaceAll('.', '-').replaceAll('_', '-')}-${DateTime.now().microsecondsSinceEpoch}',
        type: type,
        title: title,
        bounds: BoardPanelBounds(
          x: x,
          y: y,
          width: size.width,
          height: size.height,
        ),
        state: state,
        zIndex: 1,
      );
      x += size.width + gap;
      if (x > 1400) {
        x = 120;
        y += 360 + gap;
      }
      return panel;
    }

    return [
      // Row 1: notes + shape
      place(
        kMarkdownNotePluginTypeId,
        'Welcome',
        const Size(340, 260),
        {
          'markdown':
              '# YoLoIT Web Demo\n\n'
              'This board runs entirely in your browser. '
              'Try editing notes, moving cards, checking items, '
              'or adding events to the calendar.',
        },
      ),
      place(
        kStickyNotePluginTypeId,
        'Sticky',
        const Size(260, 240),
        {
          'text': 'Drag panels, resize them, and double-click to edit.',
          'color': '#FEF08A',
          'textColor': '#1F2937',
          'fontSize': 18.0,
        },
      ),
      place(
        kShapePluginTypeId,
        'Frame',
        const Size(300, 240),
        {
          'shape': 'rectangle',
          'text': 'Web shapes work too',
          'fillColor': '#0F172A',
          'strokeColor': '#38BDF8',
          'textColor': '#E2E8F0',
          'strokeWidth': 3.0,
          'fontSize': 18.0,
        },
      ),

      // Row 2: planning
      place(
        kKanbanPluginTypeId,
        'Sprint Board',
        const Size(640, 420),
        {
          'columns': ['Backlog', 'Todo', 'In Progress', 'Done'],
          'cards': [
            {
              'id': 'card-1',
              'title': 'Explore the web demo',
              'description': 'Drag cards between columns.',
              'columnIndex': 1,
            },
            {
              'id': 'card-2',
              'title': 'Edit a markdown note',
              'description': 'Double-click a note to edit.',
              'columnIndex': 2,
            },
            {
              'id': 'card-3',
              'title': 'Ship to production',
              'description': 'Done means done.',
              'columnIndex': 3,
            },
          ],
        },
      ),
      place(
        kChecklistPluginTypeId,
        'Launch Checklist',
        const Size(320, 340),
        {
          'title': 'Before go-live',
          'items': [
            {'id': 'i1', 'text': 'Review board layout', 'done': true},
            {'id': 'i2', 'text': 'Test calendar events', 'done': false},
            {'id': 'i3', 'text': 'Share with the team', 'done': false},
          ],
        },
      ),

      // Row 3: time / calendar / table / chart / webpage
      place(
        kTimerPluginTypeId,
        'Focus Timer',
        const Size(300, 360),
        {
          'duration': 1500,
          'remaining': 1500,
          'isRunning': false,
          'isPaused': false,
          'completed': false,
          'label': 'Pomodoro',
          'lastTick': 0,
        },
      ),
      place(
        kCalendarPluginTypeId,
        'Schedule',
        const Size(720, 520),
        {
          'view': 'month',
          'focusedDate': DateTime.now().toIso8601String(),
          'eventCount': 2,
          'dayStartHour': 8,
          'scrollHour': 9,
        },
      ),
      place(
        kTablePluginTypeId,
        'Sales Table',
        const Size(520, 360),
        {
          'columns': TableDataHelper.columnsToJson(TableDataHelper.defaultColumns()),
          'rows': TableDataHelper.rowsToJson(TableDataHelper.defaultRows()),
          'tableId': '',
        },
      ),
      place(
        kChartPluginTypeId,
        'Sales Chart',
        const Size(560, 400),
        {
          'type': 'line',
          'data': [
            {'month': 'Jan', 'sales': 120},
            {'month': 'Feb', 'sales': 190},
            {'month': 'Mar', 'sales': 150},
            {'month': 'Apr', 'sales': 220},
            {'month': 'May', 'sales': 280},
          ],
          'xKey': 'month',
          'yKey': 'sales',
          'groupKey': null,
          'tablePanelId': null,
          'animated': true,
        },
      ),
      place(
        kWebpagePluginTypeId,
        'YoLoIT',
        const Size(700, 500),
        {
          'url': 'https://istin.github.io/yoloit/',
          'title': '',
          'favicon': '',
        },
      ),
    ];
  }

  static Future<void> _seedCalendarEvents(List<BoardPanelInstance> panels) async {
    final calendar = panels
        .where((p) => p.type == kCalendarPluginTypeId)
        .firstOrNull;
    if (calendar == null) {
      debugPrint('[WebDemoBoardBuilder] no calendar panel found, skipping events');
      return;
    }
    const storage = CalendarEventStorage();
    final today = DateTime.now();
    await storage.upsertEvent(
      calendar.id,
      CalendarEvent(
        id: 'evt-demo-1',
        title: 'Demo kickoff',
        start: DateTime(today.year, today.month, today.day, 10),
        end: DateTime(today.year, today.month, today.day, 11),
        description: 'First look at the web board.',
      ),
    );
    await storage.upsertEvent(
      calendar.id,
      CalendarEvent(
        id: 'evt-demo-2',
        title: 'Ship review',
        start: DateTime(today.year, today.month, today.day + 2, 14),
        end: DateTime(today.year, today.month, today.day + 2, 15),
        description: 'Review shipped features.',
      ),
    );
  }
}
