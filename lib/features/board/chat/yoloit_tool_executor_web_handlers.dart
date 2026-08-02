part of 'yoloit_tool_executor_web.dart';

/// Command handlers for [YoloitWebToolExecutor].
///
/// Kept in a separate part file to satisfy the repository per-file line
/// limit. An extension in the same library has full access to the private
/// members of [YoloitWebToolExecutor], and its methods are callable like
/// instance methods from within the class.
extension _WebToolHandlers on YoloitWebToolExecutor {
  // ── Kanban ────────────────────────────────────────────────────────────────

  int _resolveColumnIndex(List<String> columns, String name) {
    for (var i = 0; i < columns.length; i++) {
      if (columns[i].trim().toLowerCase() == name.toLowerCase()) return i;
    }
    return -1;
  }

  Future<String> _handleKanbanAddCard(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final columns = _stateStringList(panel, 'columns');
      var columnIndex = _resolveColumnIndex(columns, '${args['column'] ?? ''}'.trim());
      if (columnIndex < 0) columnIndex = 0;
      final title = '${args['title'] ?? ''}'.trim();
      if (title.isEmpty) return _error('Missing card title');
      final cards = _stateList(panel, 'cards');
      cards.add(
        <String, dynamic>{
          'id': 'kanban-${DateTime.now().millisecondsSinceEpoch}',
          'title': title,
          'columnIndex': columnIndex,
        },
      );
      await _setStateList(cubit, panel, 'cards', cards);
      return _ok('kanban:add-card');
    });
  }

  Future<String> _handleKanbanCards(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final cards = _stateList(panel, 'cards');
      return _dataOk(
        'kanban:cards',
        <String, Object?>{'cards': cards, 'columns': panel.state['columns'] ?? <String>[]},
      );
    });
  }

  Future<String> _handleKanbanColumns(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final columns = _stateStringList(panel, 'columns');
      return _dataOk('kanban:columns', <String, Object?>{'columns': columns});
    });
  }

  Future<String> _handleKanbanMoveCard(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withKanbanCard(cubit, args, (panel, cards, cardIndex) async {
      final columns = _stateStringList(panel, 'columns');
      var columnIndex = _resolveColumnIndex(
        columns,
        '${args['to_column'] ?? args['to'] ?? ''}'.trim(),
      );
      if (columnIndex < 0) columnIndex = 0;
      cards[cardIndex] = <String, dynamic>{...cards[cardIndex], 'columnIndex': columnIndex};
      await _setStateList(cubit, panel, 'cards', cards);
      return _ok('kanban:move-card');
    });
  }

  Future<String> _handleKanbanUpdateCard(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withKanbanCard(cubit, args, (panel, cards, cardIndex) async {
      final title = '${args['title'] ?? ''}'.trim();
      if (title.isEmpty) return _error('Missing card title');
      cards[cardIndex] = <String, dynamic>{...cards[cardIndex], 'title': title};
      await _setStateList(cubit, panel, 'cards', cards);
      return _ok('kanban:update-card');
    });
  }

  Future<String> _handleKanbanRemoveCard(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withKanbanCard(cubit, args, (panel, cards, cardIndex) async {
      cards.removeAt(cardIndex);
      await _setStateList(cubit, panel, 'cards', cards);
      return _ok('kanban:remove-card');
    });
  }

  Future<String> _handleKanbanAddColumn(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final name = '${args['name'] ?? ''}'.trim();
      if (name.isEmpty) return _error('Missing column name');
      final columns = _stateStringList(panel, 'columns');
      columns.add(name);
      await _setStateList(cubit, panel, 'columns', columns);
      return _ok('kanban:add-column');
    });
  }

  Future<String> _handleKanbanRenameColumn(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final oldName = '${args['column'] ?? ''}'.trim();
      final newName = '${args['name'] ?? ''}'.trim();
      if (oldName.isEmpty || newName.isEmpty) {
        return _error('Missing column name or new name');
      }
      final columns = _stateStringList(panel, 'columns');
      final index = _resolveColumnIndex(columns, oldName);
      if (index < 0) return _error('Column not found');
      columns[index] = newName;
      await _setStateList(cubit, panel, 'columns', columns);
      return _ok('kanban:rename-column');
    });
  }

  Future<String> _handleKanbanRemoveColumn(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final name = '${args['column'] ?? ''}'.trim();
      if (name.isEmpty) return _error('Missing column name');
      final columns = _stateStringList(panel, 'columns');
      final index = _resolveColumnIndex(columns, name);
      if (index < 0) return _error('Column not found');
      columns.removeAt(index);
      final cards = _stateList(panel, 'cards');
      cards.removeWhere((c) => (c['columnIndex'] as int? ?? 0) == index);
      for (final card in cards) {
        final ci = card['columnIndex'] as int? ?? 0;
        if (ci > index) card['columnIndex'] = ci - 1;
      }
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: <String, dynamic>{...p.state, 'columns': columns, 'cards': cards}),
      );
      return _ok('kanban:remove-column');
    });
  }

  Future<String> _handleKanbanPaste(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final text = '${args['text'] ?? ''}'.trim();
    if (text.isEmpty) return _error('Missing card text');
    final lines = text.split('\n');
    final title = lines.first.trim();
    final description = lines.skip(1).join('\n').trim();
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final columns = _stateStringList(panel, 'columns');
      final columnHint = '${args['column'] ?? ''}'.trim();
      var columnIndex = _resolveColumnIndex(columns, columnHint);
      if (columnIndex < 0) columnIndex = 0;
      final card = <String, dynamic>{
        'id': 'kanban-${DateTime.now().millisecondsSinceEpoch}',
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'columnIndex': columnIndex,
      };
      final cards = _stateList(panel, 'cards')..add(card);
      await _setStateList(cubit, panel, 'cards', cards);
      return _ok('kanban:paste');
    });
  }

  Future<String> _withKanbanCard(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(
      BoardPanelInstance panel,
      List<Map<String, dynamic>> cards,
      int cardIndex,
    )
    action,
  ) async {
    return _withPanel(cubit, kKanbanPluginTypeId, args, (panel) async {
      final cards = _stateList(panel, 'cards');
      final cardIndex = _findEntryIndex(
        cards,
        args['card_id'] ?? args['cardId'],
        textKey: 'title',
        idKey: 'id',
      );
      if (cardIndex < 0) return _error('Card not found');
      return action(panel, cards, cardIndex);
    });
  }

  // ── Checklist ─────────────────────────────────────────────────────────────

  Future<String> _handleChecklistNew(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    if (title.isEmpty) return _error('Missing checklist title');
    await cubit.createGenericPanel(kChecklistPluginTypeId, title: title);
    return _ok('checklist:new');
  }

  Future<String> _handleChecklistAdd(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChecklistPluginTypeId, args, (panel) async {
      final itemText = '${args['item'] ?? args['text'] ?? ''}'.trim();
      if (itemText.isEmpty) return _error('Missing checklist item');
      final items = _stateList(panel, 'items');
      items.add(
        <String, dynamic>{
          'id': 'chk-${DateTime.now().millisecondsSinceEpoch}',
          'text': itemText,
          'checked': false,
        },
      );
      await _setStateList(cubit, panel, 'items', items);
      return _ok('checklist:add');
    });
  }

  Future<String> _handleChecklistItems(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChecklistPluginTypeId, args, (panel) async {
      final items = _stateList(panel, 'items');
      return _dataOk('checklist:items', <String, Object?>{'items': items});
    });
  }

  Future<String> _handleChecklistToggle(
    BoardCubit cubit,
    Map<String, Object?> args, {
    required bool checked,
  }) async {
    final itemHint = args['item'] ?? args['text'] ?? args['id'];
    return _withChecklistItem(cubit, args, itemHint, (panel, items, index) async {
      items[index] = <String, dynamic>{...items[index], 'checked': checked};
      await _setStateList(cubit, panel, 'items', items);
      return _ok(checked ? 'checklist:check' : 'checklist:uncheck');
    });
  }

  Future<String> _handleChecklistRemove(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final itemHint = args['item'] ?? args['text'] ?? args['id'];
    return _withChecklistItem(cubit, args, itemHint, (panel, items, index) async {
      items.removeAt(index);
      await _setStateList(cubit, panel, 'items', items);
      return _ok('checklist:remove');
    });
  }

  Future<String> _handleChecklistRename(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final itemHint = args['old'] ?? args['item'] ?? args['text'];
    return _withChecklistItem(cubit, args, itemHint, (panel, items, index) async {
      final newText = '${args['new'] ?? ''}'.trim();
      if (newText.isEmpty) return _error('Missing new item text');
      items[index] = <String, dynamic>{...items[index], 'text': newText};
      await _setStateList(cubit, panel, 'items', items);
      return _ok('checklist:rename');
    });
  }

  Future<String> _withChecklistItem(
    BoardCubit cubit,
    Map<String, Object?> args,
    Object? itemHint,
    Future<String> Function(
      BoardPanelInstance panel,
      List<Map<String, dynamic>> items,
      int index,
    )
    action,
  ) async {
    return _withPanel(cubit, kChecklistPluginTypeId, args, (panel) async {
      final items = _stateList(panel, 'items');
      final index = _findEntryIndex(
        items,
        itemHint,
        textKey: 'text',
        idKey: 'id',
      );
      if (index < 0) return _error('Checklist item not found');
      return action(panel, items, index);
    });
  }


  // ── Calendar ──────────────────────────────────────────────────────────────

  Future<String> _handleCalendarCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    await cubit.createGenericPanel(
      kCalendarPluginTypeId,
      title: title.isEmpty ? 'Calendar' : title,
    );
    return _ok('calendar:create');
  }

  Future<String> _handleCalendarEvents(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final events = await const CalendarEventStorage().loadEvents(panel.id);
      return _dataOk(
        'calendar:events',
        <String, Object?>{
          'events': events.map((e) => e.toJson()).toList(),
        },
      );
    });
  }

  Future<String> _handleCalendarAddEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final title = _stringArg(args, 'title');
      if (title == null) return _error('Missing event title');
      final start = _parseDateTimeArg(args, 'start');
      if (start == null) return _error('Missing or invalid start time');
      final end = _parseDateTimeArg(args, 'end');
      final allDay = _boolArg(args, 'allDay') ?? _boolArg(args, 'all_day') ?? false;
      final description = '${args['description'] ?? ''}';
      final colorValue = _parseColorValueArg(args['color']);
      final event = CalendarEvent(
        id: _nextId('event'),
        title: title,
        start: start,
        end: end,
        allDay: allDay,
        description: description,
        color: colorValue,
      );
      await const CalendarEventStorage().upsertEvent(panel.id, event);
      return _ok('calendar:add-event', extra: <String, Object?>{'id': event.id});
    });
  }

  Future<String> _handleCalendarDeleteEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withCalendarEvent(cubit, args, (panel, event) async {
      final removed = await const CalendarEventStorage().deleteEvent(
        panel.id,
        event.id,
      );
      if (!removed) return _error('Event not found');
      return _ok('calendar:delete-event');
    });
  }

  Future<String> _handleCalendarUpdateEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withCalendarEvent(cubit, args, (panel, event) async {
      final updated = event.copyWith(
        title: _stringArg(args, 'title') ?? event.title,
        start: _parseDateTimeArg(args, 'start') ?? event.start,
        end: _parseDateTimeArg(args, 'end') ?? event.end,
        allDay:
            _boolArg(args, 'allDay') ?? _boolArg(args, 'all_day') ?? event.allDay,
        description: _stringArg(args, 'description') ?? event.description,
        color: args['color'] == null ? event.color : _parseColorValueArg(args['color']),
      );
      await const CalendarEventStorage().upsertEvent(panel.id, updated);
      return _ok('calendar:update-event');
    });
  }

  Future<String> _handleCalendarSetView(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final view = '${args['view'] ?? ''}'.trim();
      if (view.isEmpty) return _error('Missing view');
      await _updatePanelState(cubit, panel, <String, dynamic>{'view': view});
      return _ok('calendar:set-view');
    });
  }

  Future<String> _handleCalendarFocusDate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final date = _parseDateTimeArg(args, 'date');
      if (date == null) return _error('Missing or invalid date');
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'focusedDate': date.toIso8601String()},
      );
      return _ok('calendar:focus-date');
    });
  }

  Future<String> _handleCalendarScrollToTime(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final hour = _intArg(args, 'hour');
      if (hour == null) return _error('Missing hour');
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'scrollHour': hour},
      );
      return _ok('calendar:scroll-to-time');
    });
  }

  Future<String> _handleCalendarScrollToEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withCalendarEvent(cubit, args, (panel, event) async {
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{
          'focusedDate': event.start.toIso8601String(),
          'selectedEventId': event.id,
        },
      );
      return _ok('calendar:scroll-to-event');
    });
  }

  Future<String> _handleCalendarShowEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withCalendarEvent(cubit, args, (panel, event) async {
      return _dataOk(
        'calendar:show-event',
        <String, Object?>{'event': event.toJson()},
      );
    });
  }

  /// Resolves the calendar panel and the event referenced by
  /// `event_id`/`eventId`, then runs [action] with both.
  Future<String> _withCalendarEvent(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(BoardPanelInstance panel, CalendarEvent event)
    action,
  ) {
    return _withPanel(cubit, kCalendarPluginTypeId, args, (panel) async {
      final eventId = '${args['event_id'] ?? args['eventId'] ?? ''}'.trim();
      if (eventId.isEmpty) return _error('Missing event id');
      final events = await const CalendarEventStorage().loadEvents(panel.id);
      final event = _firstWhereOrNull(events, (CalendarEvent e) => e.id == eventId);
      if (event == null) return _error('Event not found');
      return action(panel, event);
    });
  }

  DateTime? _parseDateTimeArg(Map<String, Object?> args, String key) {
    final value = args[key];
    if (value is DateTime) return value;
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return null;
      return DateTime.tryParse(trimmed);
    }
    return null;
  }

  int? _parseColorValueArg(Object? value) {
    if (value == null) return null;
    final color = parseColor(value.toString());
    return color?.toARGB32();
  }

  // ── Timer ─────────────────────────────────────────────────────────────────

  Future<String> _handleTimerCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final duration = _parseDurationArg(args, 'duration') ?? 300;
    final label = '${args['label'] ?? ''}'.trim();
    final panelState = <String, dynamic>{
      'duration': duration,
      'remaining': duration,
      'isRunning': false,
      'isPaused': false,
      'completed': false,
      'label': label,
      'lastTick': 0,
    };
    await cubit.createGenericPanel(
      kTimerPluginTypeId,
      title: label.isEmpty ? 'Timer' : label,
      panelState: panelState,
    );
    return _ok('timer:create');
  }

  Future<String> _handleTimerStatus(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      return _dataOk('timer:status', <String, Object?>{'state': panel.state});
    });
  }

  Future<String> _handleTimerSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      final duration = _parseDurationArg(args, 'duration');
      final label = _stringArg(args, 'label');
      final updates = <String, dynamic>{};
      if (duration != null) {
        updates['duration'] = duration;
        updates['remaining'] = duration;
        updates['isRunning'] = false;
        updates['isPaused'] = false;
        updates['completed'] = false;
      }
      if (label != null) updates['label'] = label;
      if (updates.isEmpty) return _error('No timer settings provided');
      await _updatePanelState(cubit, panel, updates);
      return _ok('timer:set');
    });
  }

  Future<String> _handleTimerStart(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      final duration = panel.state['duration'] as int? ?? 300;
      var remaining = panel.state['remaining'] as int? ?? duration;
      if (remaining <= 0) remaining = duration;
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{
          'remaining': remaining,
          'isRunning': true,
          'isPaused': false,
          'completed': false,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
        },
      );
      return _ok('timer:start');
    });
  }

  Future<String> _handleTimerPause(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      final remaining = panel.state['remaining'] as int? ?? 0;
      final lastTick = panel.state['lastTick'] as int? ?? 0;
      var newRemaining = remaining;
      if (lastTick > 0) {
        final elapsed =
            ((DateTime.now().millisecondsSinceEpoch - lastTick) / 1000).round();
        newRemaining = math.max(0, remaining - elapsed);
      }
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{
          'remaining': newRemaining,
          'isRunning': false,
          'isPaused': true,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
        },
      );
      return _ok('timer:pause');
    });
  }

  Future<String> _handleTimerResume(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{
          'isRunning': true,
          'isPaused': false,
          'lastTick': DateTime.now().millisecondsSinceEpoch,
        },
      );
      return _ok('timer:resume');
    });
  }

  Future<String> _handleTimerReset(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTimerPluginTypeId, args, (panel) async {
      final duration = panel.state['duration'] as int? ?? 300;
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{
          'remaining': duration,
          'isRunning': false,
          'isPaused': false,
          'completed': false,
        },
      );
      return _ok('timer:reset');
    });
  }

  int? _parseDurationArg(Map<String, Object?> args, String key) {
    final raw = args[key];
    if (raw is int) return raw;
    if (raw is double) return raw.toInt();
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final asInt = int.tryParse(text);
      if (asInt != null) return asInt;
      final match = RegExp(r'^(\d+)\s*([smh])$', caseSensitive: false).firstMatch(text);
      if (match != null) {
        final value = int.parse(match.group(1)!);
        return switch (match.group(2)!.toLowerCase()) {
          's' => value,
          'm' => value * 60,
          'h' => value * 3600,
          _ => value,
        };
      }
    }
    return null;
  }

  // ── Table ─────────────────────────────────────────────────────────────────

  Future<String> _handleTableCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    await cubit.createGenericPanel(
      kTablePluginTypeId,
      title: title.isEmpty ? 'Table' : title,
    );
    return _ok('table:create');
  }

  Future<String> _handleTableSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      final columns = TableDataHelper.parseColumns(_parseJsonList(args['columns']));
      final rows = TableDataHelper.parseRows(_parseJsonList(args['rows']));
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(
          state: <String, dynamic>{
            ...p.state,
            'columns': TableDataHelper.columnsToJson(columns),
            'rows': TableDataHelper.rowsToJson(rows),
          },
        ),
      );
      return _ok('table:set');
    });
  }

  Future<String> _handleTableAddRow(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      final cells = _parseJsonMap(args['cells']);
      final rows = TableDataHelper.parseRows(panel.state['rows']);
      final newRow = TableRow(id: _nextId('r'), cells: cells);
      final updated = [...rows, newRow];
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'rows': TableDataHelper.rowsToJson(updated)},
      );
      return _ok('table:add-row', extra: <String, Object?>{'id': newRow.id});
    });
  }

  Future<String> _handleTableUpdateRow(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withTableRows(cubit, args, (panel, rows, rowId) async {
      final cells = _parseJsonMap(args['cells']);
      final index = rows.indexWhere((r) => r.id == rowId);
      if (index < 0) return _error('Row not found');
      rows[index] = rows[index].copyWith(
        cells: <String, dynamic>{...rows[index].cells, ...cells},
      );
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'rows': TableDataHelper.rowsToJson(rows)},
      );
      return _ok('table:update-row');
    });
  }

  Future<String> _handleTableRemoveRow(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withTableRows(cubit, args, (panel, rows, rowId) async {
      final updated = rows.where((r) => r.id != rowId).toList();
      if (updated.length == rows.length) return _error('Row not found');
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'rows': TableDataHelper.rowsToJson(updated)},
      );
      return _ok('table:remove-row');
    });
  }

  /// Resolves the table panel, the `row_id`/`rowId` argument, and the parsed
  /// row list, then runs [action] with them.
  Future<String> _withTableRows(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(
      BoardPanelInstance panel,
      List<TableRow> rows,
      String rowId,
    )
    action,
  ) {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      final rowId = '${args['row_id'] ?? args['rowId'] ?? ''}'.trim();
      if (rowId.isEmpty) return _error('Missing row id');
      final rows = TableDataHelper.parseRows(panel.state['rows']);
      return action(panel, rows, rowId);
    });
  }

  Future<String> _handleTableAddColumn(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      final id = _stringArg(args, 'id');
      if (id == null) return _error('Missing column id');
      final title = _stringArg(args, 'title') ?? id;
      final type = TableColumnTypeExtension.fromJson(args['type']);
      final options = _parseJsonList(args['options']).cast<String>();
      final columns = TableDataHelper.parseColumns(panel.state['columns']);
      if (columns.any((c) => c.id == id)) return _error('Column already exists');
      columns.add(
        TableColumn(id: id, title: title, type: type, options: options),
      );
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'columns': TableDataHelper.columnsToJson(columns)},
      );
      return _ok('table:add-column');
    });
  }

  Future<String> _handleTableRemoveColumn(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      final colId = '${args['column_id'] ?? args['id'] ?? ''}'.trim();
      if (colId.isEmpty) return _error('Missing column id');
      final columns = TableDataHelper.parseColumns(panel.state['columns']);
      final updated = columns.where((c) => c.id != colId).toList();
      if (updated.length == columns.length) return _error('Column not found');
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'columns': TableDataHelper.columnsToJson(updated)},
      );
      return _ok('table:remove-column');
    });
  }

  Future<String> _handleTableClear(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kTablePluginTypeId, args, (panel) async {
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'rows': <Map<String, dynamic>>[]},
      );
      return _ok('table:clear');
    });
  }

  // ── Chart ─────────────────────────────────────────────────────────────────

  Future<String> _handleChartCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    final type = '${args['type'] ?? 'line'}'.trim();
    await cubit.createGenericPanel(
      kChartPluginTypeId,
      title: title.isEmpty ? 'Chart' : title,
      panelState: <String, dynamic>{'type': type},
    );
    return _ok('chart:create');
  }

  Future<String> _handleChartGet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChartPluginTypeId, args, (panel) async {
      return _dataOk('chart:get', <String, Object?>{'state': panel.state});
    });
  }

  Future<String> _handleChartSetData(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChartPluginTypeId, args, (panel) async {
      final data = _parseJsonList(args['data']);
      final updates = <String, dynamic>{'data': data};
      final xKey = _stringArg(args, 'xKey') ?? _stringArg(args, 'x_key');
      final yKey = _stringArg(args, 'yKey') ?? _stringArg(args, 'y_key');
      if (xKey != null) updates['xKey'] = xKey;
      if (yKey != null) updates['yKey'] = yKey;
      await _updatePanelState(cubit, panel, updates);
      return _ok('chart:set-data');
    });
  }

  Future<String> _handleChartSetType(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChartPluginTypeId, args, (panel) async {
      final type = '${args['type'] ?? ''}'.trim();
      if (type.isEmpty) return _error('Missing chart type');
      await _updatePanelState(cubit, panel, <String, dynamic>{'type': type});
      return _ok('chart:set-type');
    });
  }

  Future<String> _handleChartLinkTable(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChartPluginTypeId, args, (panel) async {
      final tableId = _resolveTablePanelId(
        cubit,
        args['table_panel'] ?? args['tablePanelId'] ?? args['table'],
      );
      if (tableId == null || tableId.isEmpty) {
        return _error('Linked table panel not found');
      }
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'tablePanelId': tableId},
      );
      return _ok('chart:link-table');
    });
  }

  Future<String> _handleChartRefresh(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kChartPluginTypeId, args, (panel) async {
      final tablePanelId = panel.state['tablePanelId'] as String?;
      if (tablePanelId == null || tablePanelId.isEmpty) {
        return _error('No linked table');
      }
      final tablePanel = _firstWhereOrNull(
        cubit.state.activeBoard?.panels ?? <BoardPanelInstance>[],
        (BoardPanelInstance p) => p.id == tablePanelId,
      );
      if (tablePanel == null || tablePanel.type != kTablePluginTypeId) {
        return _error('Linked table panel not found');
      }
      final rows = TableDataHelper.parseRows(tablePanel.state['rows']);
      final data = rows.map((r) => r.cells).toList();
      await _updatePanelState(cubit, panel, <String, dynamic>{'data': data});
      return _ok('chart:refresh');
    });
  }

  String? _resolveTablePanelId(BoardCubit cubit, Object? hint) {
    if (hint == null) return null;
    final panel = _findPanel(cubit, hint);
    if (panel != null && panel.type == kTablePluginTypeId) return panel.id;
    final text = '$hint'.trim();
    final board = cubit.state.activeBoard;
    if (board == null) return text;
    final byId = _firstWhereOrNull(
      board.panels,
      (BoardPanelInstance p) => p.type == kTablePluginTypeId && p.id == text,
    );
    return byId?.id ?? text;
  }

  // ── Webpage ───────────────────────────────────────────────────────────────

  Future<String> _handleWebOpen(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final url = '${args['url'] ?? ''}'.trim();
    if (url.isEmpty) return _error('Missing URL');
    final normalized = _normalizeUrl(url);
    return _withPanel(cubit, kWebpagePluginTypeId, args, (panel) async {
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'url': normalized},
      );
      return _ok('web:open');
    });
  }

  Future<String> _handleWebGet(
    BoardCubit cubit,
    Map<String, Object?> args,
    String command,
  ) async {
    return _withPanel(cubit, kWebpagePluginTypeId, args, (panel) async {
      final url = panel.state['url'] as String? ?? '';
      final title = panel.state['title'] as String? ?? '';
      switch (command) {
        case 'web:title':
          return _dataOk(command, <String, Object?>{'title': title});
        case 'web:url':
          return _dataOk(command, <String, Object?>{'url': url});
        default:
          return _dataOk(
            'web:get',
            <String, Object?>{'url': url, 'title': title},
          );
      }
    });
  }

  Future<String> _handleWebUnsupported(
    BoardCubit cubit,
    Map<String, Object?> args,
    String command,
  ) async {
    return _error(
      'Cross-origin iframes cannot be controlled from the browser; '
      '$command is not available here.',
      command: command,
    );
  }

  String _normalizeUrl(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return '';
    if (!trimmed.startsWith('http://') && !trimmed.startsWith('https://')) {
      return 'https://$trimmed';
    }
    return trimmed;
  }

  // ── UI ────────────────────────────────────────────────────────────────────

  Future<String> _handleUiCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final title = '${args['title'] ?? ''}'.trim();
    final tree = _parseJsonMap(args['tree'] ?? args['json']);
    final panelState = <String, dynamic>{
      'tree': tree.isEmpty ? UiViewPluginBase.defaultTree() : tree,
      '_scripts': <String>[],
    };
    await cubit.createGenericPanel(
      kUiViewPluginTypeId,
      title: title.isEmpty ? 'UI View' : title,
      panelState: panelState,
    );
    return _ok('ui:create');
  }

  Future<String> _handleUiRender(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kUiViewPluginTypeId, args, (panel) async {
      final tree = _parseJsonMap(args['tree'] ?? args['json']);
      if (tree.isEmpty) return _error('Missing UI tree');
      await _updatePanelState(cubit, panel, <String, dynamic>{'tree': tree});
      return _ok('ui:render');
    });
  }

  Future<String> _handleUiGet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kUiViewPluginTypeId, args, (panel) async {
      return _dataOk(
        'ui:get',
        <String, Object?>{
          'tree': panel.state['tree'],
          'scripts': panel.state['_scripts'],
        },
      );
    });
  }

  Future<String> _handleUiSetState(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kUiViewPluginTypeId, args, (panel) async {
      final stateMap = _parseJsonMap(args['state'] ?? args['json']);
      if (stateMap.isEmpty) return _error('Missing state');
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(state: <String, dynamic>{...p.state, ...stateMap}),
      );
      return _ok('ui:set-state');
    });
  }

  Future<String> _handleUiSetScripts(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withPanel(cubit, kUiViewPluginTypeId, args, (panel) async {
      final scripts = _parseJsonList(args['scripts']);
      await _updatePanelState(
        cubit,
        panel,
        <String, dynamic>{'_scripts': scripts},
      );
      return _ok('ui:set-scripts');
    });
  }

  Future<String> _handleUiEdit(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _handleUiRender(cubit, args);
  }

  // ── Board ─────────────────────────────────────────────────────────────────

  Future<String> _handleBoardsList(BoardCubit cubit) async {
    final boards =
        cubit.state.boards
            .map(
              (b) => <String, Object?>{
                'id': b.id,
                'name': b.name,
                'archived': b.archived,
                'panelCount': b.panels.length,
              },
            )
            .toList();
    return _dataOk('boards', <String, Object?>{'boards': boards});
  }

  Future<String> _handleBoardDetails(
    BoardCubit cubit,
    Map<String, Object?> args,
    String command,
  ) async {
    final BoardDocument board;
    if (command == 'board:current') {
      board = _requireActiveBoard(cubit);
    } else {
      final hint = args['id_or_name'] ?? args['board'];
      board =
          hint == null
              ? _requireActiveBoard(cubit)
              : (_findBoard(cubit, hint) ?? _requireActiveBoard(cubit));
    }
    return _dataOk(
      command,
      <String, Object?>{
        'id': board.id,
        'name': board.name,
        'archived': board.archived,
        'panelCount': board.panels.length,
        'linkCount': board.links.length,
        'groupCount': board.groups.length,
      },
    );
  }

  Future<String> _handleBoardCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final name = '${args['name'] ?? args['title'] ?? ''}'.trim();
    final board = await cubit.createBoard(
      name: name.isEmpty ? null : name,
    );
    if (board == null) return _error('Failed to create board');
    return _dataOk(
      'board:create',
      <String, Object?>{'id': board.id, 'name': board.name},
    );
  }

  Future<String> _handleBoardRename(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final newName = '${args['new_name'] ?? args['new'] ?? ''}'.trim();
    if (newName.isEmpty) return _error('Missing new name');
    await cubit.renameBoard(board.id, newName);
    return _ok('board:rename');
  }

  Future<String> _handleBoardDelete(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    await cubit.deleteBoard(board.id);
    return _ok('board:delete');
  }

  Future<String> _handleBoardArchive(
    BoardCubit cubit,
    Map<String, Object?> args, {
    required bool archive,
  }) async {
    final board = _requireActiveBoard(cubit);
    if (archive) {
      await cubit.archiveBoard(board.id);
    } else {
      await cubit.unarchiveBoard(board.id);
    }
    return _ok(archive ? 'board:archive' : 'board:unarchive');
  }

  Future<String> _handleBoardFocus(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final hint = args['id_or_name'] ?? args['board'];
    final board =
        hint == null
            ? _requireActiveBoard(cubit)
            : (_findBoard(cubit, hint) ?? _requireActiveBoard(cubit));
    await cubit.setActiveBoard(board.id);
    return _ok('board:focus');
  }

  Future<String> _handleBoardUndo(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final hadHistory = await cubit.undoLatestPanelHistory(board.id);
    return _ok('board:undo', extra: <String, Object?>{'hadHistory': hadHistory});
  }

  Future<String> _handleBoardRedo(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final hadHistory = await cubit.redoLatestPanelHistory(board.id);
    return _ok('board:redo', extra: <String, Object?>{'hadHistory': hadHistory});
  }

  Future<String> _handleBoardZoom(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final scale = _doubleArg(args, 'scale');
    if (scale == null) return _error('Missing scale');
    final viewport = board.viewport.copyWith(scale: scale.clamp(0.1, 5.0));
    await cubit.updateViewport(viewport);
    return _ok('board:zoom');
  }

  Future<String> _handleBoardFit(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final sizeText = '${args['size'] ?? args['viewport'] ?? ''}'.trim();
    var vpW = 1280.0;
    var vpH = 800.0;
    if (sizeText.isNotEmpty) {
      final parts = sizeText.split('x').map((s) => double.tryParse(s.trim())).toList();
      if (parts.length == 2 && parts[0] != null && parts[1] != null) {
        vpW = parts[0]!;
        vpH = parts[1]!;
      }
    }
    final viewport = _fitViewport(board, vpW, vpH);
    await cubit.updateViewport(viewport);
    return _ok('board:fit');
  }

  BoardViewport _fitViewport(BoardDocument board, double vpW, double vpH) {
    final panels = board.panels.where((p) => !p.hidden).toList();
    if (panels.isEmpty) return board.viewport;
    final minX = panels.map((p) => p.bounds.x).reduce(math.min);
    final minY = panels.map((p) => p.bounds.y).reduce(math.min);
    final maxX = panels.map((p) => p.bounds.x + p.bounds.width).reduce(math.max);
    final maxY = panels.map((p) => p.bounds.y + p.bounds.height).reduce(math.max);
    final contentW = math.max(1.0, maxX - minX);
    final contentH = math.max(1.0, maxY - minY);
    const padding = 80.0;
    final scaleX = (vpW - padding * 2) / contentW;
    final scaleY = (vpH - padding * 2) / contentH;
    final scale = math.min(scaleX, scaleY).clamp(0.1, 2.0);
    final tx = (vpW - contentW * scale) / 2 - minX * scale;
    final ty = (vpH - contentH * scale) / 2 - minY * scale;
    return board.viewport.copyWith(scale: scale, translation: Offset(tx, ty));
  }

  Future<String> _handleBoardTranslate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final x = _doubleArg(args, 'x');
    final y = _doubleArg(args, 'y');
    if (x == null || y == null) return _error('Missing x or y');
    final viewport = board.viewport.copyWith(translation: Offset(x, y));
    await cubit.updateViewport(viewport);
    return _ok('board:translate');
  }

  Future<String> _handleBoardArrange(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final direction = '${args['direction'] ?? ''}'.trim().toLowerCase();
    if (direction == 'grid' || direction.isEmpty) {
      await cubit.arrangePanelsByTypeInGrid(board.id);
    } else {
      await cubit.arrangePanelsInGrid(board.id);
    }
    return _ok('board:arrange');
  }

  Future<String> _handleBoardGrid(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final mode = '${args['mode'] ?? args['on_off_reset'] ?? ''}'.trim().toLowerCase();
    if (mode == 'on') {
      await cubit.setGridMode(board.id, enabled: true);
    } else if (mode == 'off') {
      await cubit.setGridMode(board.id, enabled: false);
    } else if (mode == 'reset') {
      await cubit.resetGridView(board.id);
    }
    final cell = _doubleArg(args, 'cell') ?? _doubleArg(args, 'cell_size');
    if (cell != null) await cubit.setGridCellSize(board.id, cell);
    final spacing = _doubleArg(args, 'spacing');
    if (spacing != null) await cubit.setGridSpacing(board.id, spacing);
    final arrange = _boolArg(args, 'arrange') ?? false;
    if (arrange) await cubit.arrangePanelsInGrid(board.id);
    return _ok('board:grid');
  }

  Future<String> _handleBoardSnapshot(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final panels =
        board.panels
            .map(
              (p) => <String, Object?>{
                'id': p.id,
                'type': p.type,
                'title': p.title,
                'bounds': p.bounds.toJson(),
              },
            )
            .toList();
    return _dataOk(
      'board:snapshot',
      <String, Object?>{'board': board.name, 'panels': panels},
    );
  }

  Future<String> _handleBoardDiagram(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    return _dataOk(
      'board:diagram',
      <String, Object?>{'diagram': _boardMermaid(board)},
    );
  }

  Future<String> _handleBoardSvg(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _error('SVG export is not available in the browser');
  }

  Future<String> _handleBoardApply(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final yamlText = '${args['yaml'] ?? ''}'.trim();
    final filePath = '${args['file'] ?? ''}'.trim();
    late String source;
    if (yamlText.isNotEmpty) {
      source = yamlText;
    } else if (filePath.isNotEmpty) {
      final storage = FileStorageAdapter.instance;
      if (!await storage.exists(filePath)) {
        return _error('File not found');
      }
      source = await storage.readString(filePath) ?? '';
    } else {
      return _error('Missing YAML operations');
    }
    final doc = loadYaml(source);
    final List<dynamic> list =
        doc is YamlList
            ? doc.nodes
            : (doc is List ? doc : <dynamic>[]);
    final operations =
        list
            .whereType<YamlMap>()
            .map(
              (YamlMap e) => Map<String, dynamic>.from(
                e.nodes.map(
                  (dynamic k, YamlNode v) =>
                      MapEntry(k.toString(), v.value),
                ),
              ),
            )
            .toList();
    const applier = BoardOperationApplier();
    await applier.apply(cubit, board, operations);
    return _ok('board:apply');
  }

  String _boardMermaid(BoardDocument board) {
    final sb = StringBuffer('graph LR\n');
    for (final p in board.panels) {
      sb.writeln('  ${p.id}["${p.title}"]');
    }
    for (final l in board.links) {
      sb.writeln('  ${l.fromPanelId} --> ${l.toPanelId}');
    }
    return sb.toString();
  }

  Future<String> _handleSelect(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final panelsArg = args['panels'];
    if (panelsArg != null) {
      final ids = _resolvePanelIds(cubit, panelsArg);
      cubit.selectPanels(ids);
      return _ok('select', extra: <String, Object?>{'selected': ids.toList()});
    }
    final rectArg = '${args['rect'] ?? ''}'.trim();
    if (rectArg.isNotEmpty) {
      final parts =
          rectArg.split(',').map((s) => double.tryParse(s.trim())).toList();
      if (parts.length == 4 && parts.every((v) => v != null)) {
        cubit.selectPanelsInRect(
          Rect.fromLTWH(parts[0]!, parts[1]!, parts[2]!, parts[3]!),
        );
        return _ok('select');
      }
    }
    return _dataOk(
      'select',
      <String, Object?>{'selected': cubit.state.selectedPanelIds.toList()},
    );
  }

  // ── Drawings ──────────────────────────────────────────────────────────────

  Future<String> _handleDrawList(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    return _dataOk(
      'draw:list',
      <String, Object?>{
        'drawings': board.drawings.map((d) => d.toJson()).toList(),
      },
    );
  }

  Future<String> _handleDrawAdd(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final type = '${args['type'] ?? ''}'.trim().toLowerCase();
    final color = parseColor('${args['color'] ?? ''}') ?? Colors.blue;
    final width = _doubleArg(args, 'width') ?? _doubleArg(args, 'w') ?? 3.0;
    final drawing = switch (type) {
      'line' => _buildLineDrawing(args, color, width, arrow: false),
      'arrow' => _buildLineDrawing(args, color, width, arrow: true),
      'rect' => _buildRectDrawing(args, color, width),
      'circle' => _buildCircleDrawing(args, color, width),
      'freehand' => _buildFreehandDrawing(args, color, width),
      _ => null,
    };
    if (drawing == null) return _error('Unsupported draw type: $type');
    await cubit.addDrawing(drawing);
    return _ok('draw:add', extra: <String, Object?>{'id': drawing.id});
  }

  Future<String> _handleDrawRemove(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final drawingId = '${args['id'] ?? args['drawing_id'] ?? ''}'.trim();
    if (drawingId.isEmpty) return _error('Missing drawing id');
    await cubit.removeDrawing(drawingId);
    return _ok('draw:remove');
  }

  Future<String> _handleDrawClear(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    for (final d in board.drawings) {
      await cubit.removeDrawing(d.id);
    }
    return _ok('draw:clear');
  }

  Future<String> _handleDrawSvg(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _error('SVG path drawing is not supported in the browser');
  }

  Future<String> _handleDrawExport(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final svg = _drawingsToSvg(board.drawings);
    return _dataOk('draw:export', <String, Object?>{'svg': svg});
  }

  BoardDrawingElement _buildLineDrawing(
    Map<String, Object?> args,
    Color color,
    double width, {
    required bool arrow,
  }) {
    final x1 = _doubleArg(args, 'x1') ?? _doubleArg(args, 'x') ?? 0.0;
    final y1 = _doubleArg(args, 'y1') ?? _doubleArg(args, 'y') ?? 0.0;
    final x2 = _doubleArg(args, 'x2') ?? 100.0;
    final y2 = _doubleArg(args, 'y2') ?? 100.0;
    return BoardDrawingElement.fromRawStroke(
      id: _nextId('draw'),
      rawPoints: <Offset>[Offset(x1, y1), Offset(x2, y2)],
      strokeColor: color,
      strokeWidth: width,
    );
  }

  BoardDrawingElement _buildRectDrawing(
    Map<String, Object?> args,
    Color color,
    double width,
  ) {
    final x = _doubleArg(args, 'x') ?? 0.0;
    final y = _doubleArg(args, 'y') ?? 0.0;
    final w = _doubleArg(args, 'width') ?? 100.0;
    final h = _doubleArg(args, 'height') ?? 100.0;
    return BoardDrawingElement.fromRawStroke(
      id: _nextId('draw'),
      rawPoints: <Offset>[
        Offset(x, y),
        Offset(x + w, y),
        Offset(x + w, y + h),
        Offset(x, y + h),
        Offset(x, y),
      ],
      strokeColor: color,
      strokeWidth: width,
    );
  }

  BoardDrawingElement _buildCircleDrawing(
    Map<String, Object?> args,
    Color color,
    double width,
  ) {
    final cx = _doubleArg(args, 'cx') ?? _doubleArg(args, 'x') ?? 50.0;
    final cy = _doubleArg(args, 'cy') ?? _doubleArg(args, 'y') ?? 50.0;
    final r = _doubleArg(args, 'r') ?? _doubleArg(args, 'radius') ?? 50.0;
    final points = <Offset>[];
    const segments = 32;
    for (var i = 0; i <= segments; i++) {
      final angle = 2 * math.pi * i / segments;
      points.add(Offset(cx + r * math.cos(angle), cy + r * math.sin(angle)));
    }
    return BoardDrawingElement.fromRawStroke(
      id: _nextId('draw'),
      rawPoints: points,
      strokeColor: color,
      strokeWidth: width,
    );
  }

  BoardDrawingElement _buildFreehandDrawing(
    Map<String, Object?> args,
    Color color,
    double width,
  ) {
    final raw = _parseJsonList(args['points']);
    final points = <Offset>[];
    for (final entry in raw) {
      if (entry is List && entry.length >= 2) {
        final x = (entry[0] as num?)?.toDouble() ?? 0.0;
        final y = (entry[1] as num?)?.toDouble() ?? 0.0;
        points.add(Offset(x, y));
      }
    }
    if (points.isEmpty) {
      return BoardDrawingElement.fromRawStroke(
        id: _nextId('draw'),
        rawPoints: <Offset>[Offset.zero, const Offset(100, 100)],
        strokeColor: color,
        strokeWidth: width,
      );
    }
    return BoardDrawingElement.fromRawStroke(
      id: _nextId('draw'),
      rawPoints: points,
      strokeColor: color,
      strokeWidth: width,
    );
  }

  String _drawingsToSvg(List<BoardDrawingElement> drawings) {
    final sb =
        StringBuffer(
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 2000 2000">\n',
        );
    for (final d in drawings) {
      final color = '#${d.strokeColor.toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      for (final stroke in d.strokes) {
        if (stroke.isEmpty) continue;
        final pts =
            stroke
                .map(
                  (p) => '${(d.position.dx + p.dx).toStringAsFixed(1)},${(d.position.dy + p.dy).toStringAsFixed(1)}',
                )
                .join(' ');
        sb.writeln(
          '  <polyline points="$pts" fill="none" stroke="$color" '
          'stroke-width="${d.strokeWidth}" />',
        );
      }
    }
    sb.writeln('</svg>');
    return sb.toString();
  }

  // ── Links ─────────────────────────────────────────────────────────────────

  Future<String> _handleLinksList(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    return _dataOk(
      'links',
      <String, Object?>{
        'links':
            board.links
                .map(
                  (l) => <String, Object?>{
                    'id': l.id,
                    'from': l.fromPanelId,
                    'to': l.toPanelId,
                    'style': l.style.name,
                    'geometry': l.geometry.name,
                  },
                )
                .toList(),
      },
    );
  }

  Future<String> _handleLinkCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final fromHint = args['from'] ?? args['from_panel'] ?? args['fromPanelId'];
    final toHint = args['to'] ?? args['to_panel'] ?? args['toPanelId'];
    final fromPanel = _findPanel(cubit, fromHint);
    final toPanel = _findPanel(cubit, toHint);
    if (fromPanel == null || toPanel == null) {
      return _error('Source or target panel not found');
    }
    final link = BoardPanelLink(
      id: _nextId('link'),
      fromPanelId: fromPanel.id,
      toPanelId: toPanel.id,
    );
    await cubit.upsertLink(link);
    return _ok('link:create', extra: <String, Object?>{'id': link.id});
  }

  Future<String> _handleLinkDelete(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final linkId = '${args['link_id'] ?? args['linkId'] ?? ''}'.trim();
    if (linkId.isEmpty) return _error('Missing link id');
    await cubit.removeLink(linkId);
    return _ok('link:delete');
  }

  Future<String> _handleLinkStyle(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final linkId = '${args['link_id'] ?? args['linkId'] ?? ''}'.trim();
    if (linkId.isEmpty) return _error('Missing link id');
    final styleText = '${args['style'] ?? ''}'.trim();
    final geometryText = '${args['geometry'] ?? ''}'.trim();
    final board = _requireActiveBoard(cubit);
    final link = _firstWhereOrNull(board.links, (BoardPanelLink l) => l.id == linkId);
    if (link == null) return _error('Link not found');
    final style = BoardLinkStyle.values.firstWhere(
      (s) => s.name == styleText,
      orElse: () => link.style,
    );
    final geometry = BoardLinkGeometry.values.firstWhere(
      (g) => g.name == geometryText,
      orElse: () => link.geometry,
    );
    await cubit.upsertLink(
      link.copyWith(style: style, geometry: geometry),
    );
    return _ok('link:style');
  }

  Future<String> _handleLinkColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final linkId = '${args['link_id'] ?? args['linkId'] ?? ''}'.trim();
    final color = parseColor('${args['color'] ?? ''}');
    if (linkId.isEmpty) return _error('Missing link id');
    if (color == null) return _error('Missing or invalid color');
    final board = _requireActiveBoard(cubit);
    final link = _firstWhereOrNull(board.links, (BoardPanelLink l) => l.id == linkId);
    if (link == null) return _error('Link not found');
    await cubit.upsertLink(link.copyWith(color: color));
    return _ok('link:color');
  }

  // ── Groups ────────────────────────────────────────────────────────────────

  Future<String> _handleGroupsList(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    return _dataOk(
      'groups',
      <String, Object?>{
        'groups':
            board.groups
                .map(
                  (g) => <String, Object?>{
                    'id': g.id,
                    'name': g.name,
                    'panelIds': g.panelIds,
                    'collapsed': g.collapsed,
                  },
                )
                .toList(),
      },
    );
  }

  Future<String> _handleGroupCreate(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final board = _requireActiveBoard(cubit);
    final name = '${args['name'] ?? ''}'.trim();
    final panelIds =
        _resolvePanelIds(cubit, args['panels'] ?? args['panel_ids']).toList();
    final color = parseColor('${args['color'] ?? ''}')?.toARGB32();
    await cubit.createGroup(
      board.id,
      name: name.isEmpty ? 'Group' : name,
      panelIds: panelIds,
      color: color,
    );
    return _ok('group:create');
  }

  Future<String> _handleGroupDelete(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      await cubit.deleteGroup(board.id, group.id);
      return _ok('group:delete');
    });
  }

  Future<String> _handleGroupRename(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      final newName = '${args['name'] ?? args['new_name'] ?? ''}'.trim();
      if (newName.isEmpty) return _error('Missing new name');
      await cubit.renameGroup(board.id, group.id, newName);
      return _ok('group:rename');
    });
  }

  Future<String> _handleGroupColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      final color = parseColor('${args['color'] ?? ''}')?.toARGB32();
      await cubit.setGroupColor(board.id, group.id, color);
      return _ok('group:color');
    });
  }

  Future<String> _handleGroupAdd(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _handleGroupAddRemove(cubit, args, add: true);
  }

  Future<String> _handleGroupRemove(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _handleGroupAddRemove(cubit, args, add: false);
  }

  Future<String> _handleGroupAddRemove(
    BoardCubit cubit,
    Map<String, Object?> args, {
    required bool add,
  }) async {
    return _withGroup(cubit, args, (board, group) async {
      final panelIds =
          _resolvePanelIds(cubit, args['panels'] ?? args['panel_ids']).toList();
      if (panelIds.isEmpty) return _error(add ? 'No panels to add' : 'No panels to remove');
      if (add) {
        await cubit.addPanelsToGroup(board.id, group.id, panelIds);
      } else {
        await cubit.removePanelsFromGroup(board.id, group.id, panelIds);
      }
      return _ok(add ? 'group:add' : 'group:remove');
    });
  }

  Future<String> _handleGroupCollapseExpand(
    BoardCubit cubit,
    Map<String, Object?> args,
    bool collapse,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      if (group.collapsed == collapse) {
        return _ok(collapse ? 'group:collapse' : 'group:expand');
      }
      await cubit.toggleGroupCollapse(board.id, group.id);
      return _ok(collapse ? 'group:collapse' : 'group:expand');
    });
  }

  Future<String> _handleGroupMove(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      final x = _doubleArg(args, 'x') ?? _doubleArg(args, 'dx') ?? 0.0;
      final y = _doubleArg(args, 'y') ?? _doubleArg(args, 'dy') ?? 0.0;
      await cubit.moveGroup(board.id, group.id, Offset(x, y));
      return _ok('group:move');
    });
  }

  Future<String> _handleGroupCycleFocus(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withGroup(cubit, args, (board, group) async {
      final direction = _intArg(args, 'direction') ?? 1;
      await cubit.cycleGroupFocus(board.id, group.id, direction);
      return _ok('group:cycle-focus');
    });
  }

  /// Resolves the active board and the group referenced by
  /// `group`/`group_id`/`id`, then runs [action] with both.
  Future<String> _withGroup(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(BoardDocument board, BoardPanelGroup group) action,
  ) async {
    final board = _requireActiveBoard(cubit);
    final group = _findGroup(board, args['group'] ?? args['group_id'] ?? args['id']);
    if (group == null) return _error('Group not found');
    return action(board, group);
  }

  BoardPanelGroup? _findGroup(BoardDocument board, Object? hint) {
    if (hint == null) return null;
    final text = '$hint'.trim().toLowerCase();
    if (text.isEmpty) return null;
    for (final group in board.groups) {
      if (group.id.toLowerCase() == text ||
          group.name.trim().toLowerCase() == text) {
        return group;
      }
    }
    return null;
  }

  // ── YoLo chat ─────────────────────────────────────────────────────────────

  Future<String> _handleYolochatSend(
    BoardCubit cubit,
    Map<String, Object?> args,
    ChatRuntimeContext? runtimeContext,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      final text = '${args['text'] ?? ''}'.trim();
      if (text.isEmpty) return _error('Missing message text');
      final config = _chatConfigFromPanel(panel);
      final session = ChatSessionManager.instance.getOrCreate(panel.id, config);
      final sent = await session.sendMessage(
        text: text,
        runtimeContext: runtimeContext,
      );
      if (!sent) return _error('Could not send message');
      await _persistChatPanelState(cubit, panel, session);
      return _ok('yolochat:send');
    });
  }

  Future<String> _handleYolochatMessages(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      final session = ChatSessionManager.instance.get(panel.id);
      List<Map<String, dynamic>> messages;
      if (session != null) {
        messages = session.messages.map((m) => m.toJson()).toList();
      } else {
        final raw = panel.state['messages'] as List? ?? const [];
        messages =
            raw
                .whereType<Map<String, dynamic>>()
                .map((m) => Map<String, dynamic>.from(m))
                .toList();
      }
      return _dataOk(
        'yolochat:messages',
        <String, Object?>{'messages': messages},
      );
    });
  }

  Future<String> _handleYolochatClear(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      final session = ChatSessionManager.instance.get(panel.id);
      session?.clearMessages();
      await cubit.updatePanel(
        panel.id,
        (p) => p.copyWith(
          state: <String, dynamic>{...p.state, 'messages': <Map<String, dynamic>>[]},
        ),
      );
      return _ok('yolochat:clear');
    });
  }

  Future<String> _handleYolochatStatus(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      final session = ChatSessionManager.instance.get(panel.id);
      return _dataOk(
        'yolochat:status',
        <String, Object?>{
          'isProcessing': session?.isProcessing ?? false,
          'panelId': panel.id,
        },
      );
    });
  }

  Future<String> _handleYolochatStop(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      final session = ChatSessionManager.instance.get(panel.id);
      if (session != null) {
        await session.stopStreaming();
        await _persistChatPanelState(cubit, panel, session);
      }
      return _ok('yolochat:stop');
    });
  }

  Future<String> _handleYolochatSessions(BoardCubit cubit) async {
    final ids = ChatSessionManager.instance.activeSessionIds;
    return _dataOk(
      'yolochat:sessions',
      <String, Object?>{'sessions': ids},
    );
  }

  Future<String> _handleYolochatConfig(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    return _withChatPanel(cubit, args, (panel) async {
      var config = _chatConfigFromPanel(panel);
      final provider = _stringArg(args, 'provider');
      final model = _stringArg(args, 'model');
      if (provider != null || model != null) {
        config = config.copyWith(provider: provider, model: model);
        final session = ChatSessionManager.instance.getOrCreate(panel.id, config);
        session.updateConfig(config);
        await _persistChatPanelState(cubit, panel, session);
      }
      return _dataOk(
        'yolochat:config',
        <String, Object?>{'config': config.toJson()},
      );
    });
  }

  /// Resolves the AI Chat panel referenced by `panel`/`p`, then runs
  /// [action] with it.
  Future<String> _withChatPanel(
    BoardCubit cubit,
    Map<String, Object?> args,
    Future<String> Function(BoardPanelInstance panel) action,
  ) async {
    final panel = _findPanelByType(
      cubit,
      kChatPluginTypeId,
      hint: args['panel'] ?? args['p'],
    );
    if (panel == null) return _error('AI Chat panel not found');
    return action(panel);
  }

  ChatSessionConfig _chatConfigFromPanel(BoardPanelInstance panel) {
    final raw = panel.state['config'];
    if (raw is Map) {
      return ChatSessionConfig.fromJson(
        Map<String, dynamic>.from(raw),
      );
    }
    return const ChatSessionConfig(sessionName: 'chat', workingDir: '');
  }

  Future<void> _persistChatPanelState(
    BoardCubit cubit,
    BoardPanelInstance panel,
    ChatSession session,
  ) async {
    await cubit.updatePanel(
      panel.id,
      (p) => p.copyWith(
        state: <String, dynamic>{...p.state, ...session.serializeState()},
      ),
    );
  }

  // ── Themes ────────────────────────────────────────────────────────────────

  Future<String> _handleTheme(BoardCubit cubit) async {
    final tm = ThemeManager.instance;
    return _dataOk(
      'theme',
      <String, Object?>{
        'preset': tm.current.name,
        'brightness': tm.brightness.name,
        'customThemeId': tm.activeCustomThemeId,
        'hasOverrides': tm.hasOverrides,
      },
    );
  }

  Future<String> _handleThemePresets(BoardCubit cubit) async {
    final presets =
        AppThemePreset.values
            .map((p) => <String, Object?>{'name': p.name, 'label': p.label})
            .toList();
    return _dataOk('theme:presets', <String, Object?>{'presets': presets});
  }

  Future<String> _handleThemeSet(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final name = '${args['name'] ?? args['preset'] ?? ''}'.trim();
    final preset = _firstWhereOrNull(
      AppThemePreset.values,
      (AppThemePreset p) => p.name == name || p.label.toLowerCase() == name.toLowerCase(),
    );
    if (preset == null) return _error('Unknown preset');
    await ThemeManager.instance.setTheme(preset);
    return _ok('theme:set');
  }

  Future<String> _handleThemeBrightness(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final mode = '${args['mode'] ?? args['brightness'] ?? ''}'.trim().toLowerCase();
    final brightness =
        mode == 'light'
            ? Brightness.light
            : (mode == 'dark' ? Brightness.dark : null);
    if (brightness == null) return _error('Brightness must be light or dark');
    await ThemeManager.instance.setBrightness(brightness);
    return _ok('theme:brightness');
  }

  Future<String> _handleThemeColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final slot = '${args['slot'] ?? ''}'.trim();
    final color = parseColor('${args['color'] ?? ''}');
    if (slot.isEmpty) return _error('Missing color slot');
    if (color == null) return _error('Missing or invalid color');
    await ThemeManager.instance.setColorOverride(slot, color);
    return _ok('theme:color');
  }

  Future<String> _handleThemeResetColor(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final slot = '${args['slot'] ?? ''}'.trim();
    if (slot.isEmpty) return _error('Missing color slot');
    await ThemeManager.instance.removeColorOverride(slot);
    return _ok('theme:reset-color');
  }

  Future<String> _handleThemeResetAll(BoardCubit cubit) async {
    await ThemeManager.instance.clearColorOverrides();
    return _ok('theme:reset-all');
  }

  Future<String> _handleThemeSave(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final name = '${args['name'] ?? ''}'.trim();
    if (name.isEmpty) return _error('Missing theme name');
    final id = await ThemeManager.instance.saveCurrentAsPreset(name);
    return _ok('theme:save', extra: <String, Object?>{'id': id});
  }

  Future<String> _handleThemeExport(BoardCubit cubit) async {
    final json = ThemeManager.instance.exportCurrentAsJson();
    return _dataOk('theme:export', <String, Object?>{'json': json});
  }

  Future<String> _handleThemeColors(BoardCubit cubit) async {
    final tm = ThemeManager.instance;
    final colors = <String, String>{};
    for (final entry in ThemeManager.colorCategories.entries) {
      for (final slot in entry.value) {
        colors[slot.key] =
            '#${tm.colorForSlot(slot.key).toARGB32().toRadixString(16).padLeft(8, '0').substring(2)}';
      }
    }
    return _dataOk('theme:colors', <String, Object?>{'colors': colors});
  }

  Future<String> _handleThemeSlots(BoardCubit cubit) async {
    final slots =
        ThemeManager.colorCategories.entries
            .expand(
              (e) => e.value.map(
                (s) => <String, Object?>{
                  'category': e.key,
                  'key': s.key,
                  'label': s.label,
                },
              ),
            )
            .toList();
    return _dataOk('theme:slots', <String, Object?>{'slots': slots});
  }

  Future<String> _handleThemeDelete(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final id = '${args['id'] ?? ''}'.trim();
    if (id.isEmpty) return _error('Missing theme id');
    await ThemeManager.instance.deleteCustomTheme(id);
    return _ok('theme:delete');
  }

  // ── Help / search ─────────────────────────────────────────────────────────

  Future<String> _handleHelp(Map<String, Object?> args) async {
    final format = '${args['format'] ?? 'tools'}'.trim();
    if (format == 'tools') {
      return YoloitCliToolCatalog.compactToolsJson();
    }
    final tools =
        YoloitCliToolCatalog.tools
            .map(
              (YoloitCliTool t) => <String, Object?>{
                'command': t.command,
                'group': t.group,
                'description': t.description,
              },
            )
            .toList();
    return _dataOk('help', <String, Object?>{'commands': tools});
  }

  Future<String> _handleSearch(
    BoardCubit cubit,
    Map<String, Object?> args,
  ) async {
    final query = '${args['query'] ?? ''}'.trim().toLowerCase();
    if (query.isEmpty) {
      return _dataOk('search', <String, Object?>{'results': <Object?>[]});
    }
    final results = <Map<String, Object?>>[];
    final board = _requireActiveBoard(cubit);
    for (final panel in board.panels) {
      if (panel.title.toLowerCase().contains(query)) {
        results.add(
          <String, Object?>{
            'type': 'panel',
            'id': panel.id,
            'title': panel.title,
          },
        );
      }
      final stateText = jsonEncode(panel.state).toLowerCase();
      if (stateText.contains(query)) {
        results.add(
          <String, Object?>{
            'type': 'panel_state',
            'id': panel.id,
            'title': panel.title,
          },
        );
      }
    }
    for (final session in ChatSessionManager.instance.sessions.values) {
      for (final msg in session.messages) {
        if (msg.content.toLowerCase().contains(query)) {
          results.add(
            <String, Object?>{
              'type': 'chat_message',
              'panelId': session.panelId,
              'role': msg.role.name,
              'content': msg.content,
            },
          );
        }
      }
    }
    return _dataOk('search', <String, Object?>{'results': results});
  }
}
