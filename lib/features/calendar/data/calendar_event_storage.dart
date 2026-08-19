import 'dart:convert';

import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/remote/history_store_helpers.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

/// File-backed storage for calendar events.
///
/// Events are stored per panel so that large event payloads do not bloat the
/// board document. The board only keeps lightweight metadata (view, focused
/// date, cached event count) in the panel state.
///
/// On desktop this is backed by real files under `PlatformDirs.instance.dataDir`;
/// on web it is backed by [FileStorageAdapter] using browser storage.
class CalendarEventStorage {
  const CalendarEventStorage();

  static const _baseDir = 'calendar_events';

  // Hoisted encoder — was allocated per save call.
  static const JsonEncoder _prettyEncoder = JsonEncoder.withIndent('  ');

  String _filePath(String panelId) {
    final safeId = HistoryStoreHelpers.safeSegment(panelId);
    return '$_baseDir/$safeId.json';
  }

  /// Loads all events for a panel.
  Future<List<CalendarEvent>> loadEvents(String panelId) async {
    final path = _filePath(panelId);
    final storage = FileStorageAdapter.instance;
    if (!await storage.exists(path)) return const [];
    try {
      final text = await storage.readString(path);
      final decoded = jsonDecode(text ?? '[]');
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
    final path = _filePath(panelId);
    final payload = events.map((e) => e.toJson()).toList();
    await FileStorageAdapter.instance.writeString(
      path,
      _prettyEncoder.convert(payload),
    );
  }

  /// Adds or updates a single event.
  Future<CalendarEvent> upsertEvent(String panelId, CalendarEvent event) async {
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
    final sourcePath = _filePath(sourcePanelId);
    final storage = FileStorageAdapter.instance;
    if (!await storage.exists(sourcePath)) return;
    final text = await storage.readString(sourcePath);
    if (text == null || text.isEmpty) return;
    await storage.writeString(_filePath(targetPanelId), text);
  }

  /// Deletes all stored events for a panel.
  Future<void> clearEvents(String panelId) async {
    await FileStorageAdapter.instance.delete(_filePath(panelId));
  }

  /// Counts events for a panel without building the full list.
  Future<int> countEvents(String panelId) async {
    final path = _filePath(panelId);
    final storage = FileStorageAdapter.instance;
    if (!await storage.exists(path)) return 0;
    try {
      final text = await storage.readString(path);
      final decoded = jsonDecode(text ?? '[]');
      if (decoded is List) return decoded.length;
    } on FormatException {
      // fall through
    }
    return 0;
  }
}
