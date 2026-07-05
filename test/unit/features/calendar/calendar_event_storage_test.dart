import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/calendar/data/calendar_event_storage.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmpDir;
  late CalendarEventStorage storage;

  setUp(() async {
    tmpDir = Directory.systemTemp.createTempSync('calendar_storage_test');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: tmpDir.path));
    storage = const CalendarEventStorage();
    // The service now uses scoped paths via [FileStorageAdapter]; remove any
    // leftovers from earlier test runs.
    final fallback = Directory('calendar_events');
    if (fallback.existsSync()) {
      fallback.deleteSync(recursive: true);
    }
  });

  tearDown(() async {
    // Clean up the scoped path used by [FileStorageAdapter] on the VM.
    try {
      final fallback = Directory('calendar_events');
      if (fallback.existsSync()) {
        fallback.deleteSync(recursive: true);
      }
    } catch (_) {}
    if (tmpDir.existsSync()) {
      tmpDir.deleteSync(recursive: true);
    }
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  test('loadEvents returns empty list when file does not exist', () async {
    final events = await storage.loadEvents('panel-1');
    expect(events, isEmpty);
  });

  test('saveEvents and loadEvents round-trip', () async {
    final event = CalendarEvent(
      id: 'ev-1',
      title: 'Standup',
      start: DateTime(2026, 6, 19, 10, 0),
      end: DateTime(2026, 6, 19, 11, 0),
      allDay: false,
      description: 'Daily sync',
      color: 0xFF3B82F6,
    );
    await storage.saveEvents('panel-1', [event]);
    final loaded = await storage.loadEvents('panel-1');
    expect(loaded.length, 1);
    expect(loaded.first.id, 'ev-1');
    expect(loaded.first.title, 'Standup');
    expect(loaded.first.start, DateTime(2026, 6, 19, 10, 0));
    expect(loaded.first.end, DateTime(2026, 6, 19, 11, 0));
    expect(loaded.first.allDay, false);
    expect(loaded.first.description, 'Daily sync');
    expect(loaded.first.color, 0xFF3B82F6);
  });

  test('upsertEvent adds and updates events', () async {
    final event = CalendarEvent(
      id: 'ev-1',
      title: 'Standup',
      start: DateTime(2026, 6, 19, 10, 0),
    );
    await storage.upsertEvent('panel-2', event);
    expect(await storage.countEvents('panel-2'), 1);

    final updated = event.copyWith(title: 'Updated standup');
    await storage.upsertEvent('panel-2', updated);
    final loaded = await storage.loadEvents('panel-2');
    expect(loaded.length, 1);
    expect(loaded.first.title, 'Updated standup');
  });

  test('deleteEvent removes event', () async {
    final event = CalendarEvent(
      id: 'ev-1',
      title: 'Standup',
      start: DateTime(2026, 6, 19, 10, 0),
    );
    await storage.upsertEvent('panel-3', event);
    final ok = await storage.deleteEvent('panel-3', 'ev-1');
    expect(ok, true);
    expect(await storage.countEvents('panel-3'), 0);
  });

  test('deleteEvent returns false when event not found', () async {
    final ok = await storage.deleteEvent('panel-4', 'missing');
    expect(ok, false);
  });

  test('copyEvents copies file to new panel', () async {
    final event = CalendarEvent(
      id: 'ev-1',
      title: 'Standup',
      start: DateTime(2026, 6, 19, 10, 0),
    );
    await storage.upsertEvent('source-panel', event);
    await storage.copyEvents('source-panel', 'target-panel');
    final copied = await storage.loadEvents('target-panel');
    expect(copied.length, 1);
    expect(copied.first.title, 'Standup');
  });
}
