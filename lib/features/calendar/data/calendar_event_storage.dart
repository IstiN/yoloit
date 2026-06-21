import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

/// File-backed storage for calendar events.
///
/// Events are stored per panel so that large event payloads do not bloat the
/// board document. The board only keeps lightweight metadata (view, focused
/// date, cached event count) in the panel state.
class CalendarEventStorage {
  const CalendarEventStorage();

  String get _baseDir => p.join(
    PlatformDirs.instance.dataDir,
    'calendar_events',
  );

  String _filePath(String panelId) {
    final safeId = HistoryStoreHelpers.safeSegment(panelId);
    return p.join(_baseDir, '$safeId.json');
  }

  /// Loads all events for a panel.
  Future<List<CalendarEvent>> loadEvents(String panelId) async {
    final file = File(_filePath(panelId));
    if (!await file.exists()) return const [];
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(CalendarEvent.fromJson)
          .toList();
    } on FormatException {
      return const [];
    }
  }

  /// Saves the complete event list for a panel.
  Future<void> saveEvents(String panelId, List<CalendarEvent> events) async {
    final file = File(_filePath(panelId));
    final payload = events.map((e) => e.toJson()).toList();
    await HistoryStoreHelpers.writeJsonAtomic(file, payload);
  }

  /// Adds or updates a single event.
  Future<CalendarEvent> upsertEvent(
    String panelId,
    CalendarEvent event,
  ) async {
    final events = await loadEvents(panelId);
    final index = events.indexWhere((e) => e.id == event.id);
    final List<CalendarEvent> updated;
    if (index >= 0) {
      updated = [...events];
      updated[index] = event;
    } else {
      updated = [...events, event];
    }
    await saveEvents(panelId, updated);
    return event;
  }

  /// Deletes an event by id.
  Future<bool> deleteEvent(String panelId, String eventId) async {
    final events = await loadEvents(panelId);
    final before = events.length;
    final filtered = events.where((e) => e.id != eventId).toList();
    if (filtered.length == before) return false;
    await saveEvents(panelId, filtered);
    return true;
  }

  /// Copies all events from one panel to another.
  Future<void> copyEvents(String sourcePanelId, String targetPanelId) async {
    final sourceFile = File(_filePath(sourcePanelId));
    if (!await sourceFile.exists()) return;
    final targetFile = File(_filePath(targetPanelId));
    await targetFile.parent.create(recursive: true);
    await sourceFile.copy(targetFile.path);
  }

  /// Deletes all stored events for a panel.
  Future<void> clearEvents(String panelId) async {
    final file = File(_filePath(panelId));
    if (await file.exists()) {
      await file.delete();
    }
  }

  /// Counts events for a panel without building the full list.
  Future<int> countEvents(String panelId) async {
    final file = File(_filePath(panelId));
    if (!await file.exists()) return 0;
    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) return decoded.length;
    } on FormatException {
      // fall through
    }
    return 0;
  }
}
