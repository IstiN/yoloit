import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/calendar/model/calendar_event.dart';

void main() {
  group('CalendarEvent', () {
    test('toJson / fromJson round-trip', () {
      final event = CalendarEvent(
        id: 'ev-1',
        title: 'Sprint planning',
        start: DateTime(2026, 6, 19, 14, 0),
        end: DateTime(2026, 6, 19, 15, 30),
        allDay: false,
        description: 'Plan next sprint',
        color: Colors.blue.toARGB32(),
        meetingUrl: 'https://meet.example.com/standup',
      );
      final json = event.toJson();
      final restored = CalendarEvent.fromJson(json);

      expect(restored.id, event.id);
      expect(restored.title, event.title);
      expect(restored.start, event.start);
      expect(restored.end, event.end);
      expect(restored.allDay, event.allDay);
      expect(restored.description, event.description);
      expect(restored.color, event.color);
      expect(restored.meetingUrl, event.meetingUrl);
    });

    test('toJson omits null meetingUrl', () {
      final event = CalendarEvent(
        id: 'ev-1',
        title: 'Sprint planning',
        start: DateTime(2026, 6, 19, 14, 0),
      );
      final json = event.toJson();
      expect(json.containsKey('meetingUrl'), isFalse);
    });

    test('fromJson parses hex color string', () {
      final json = <String, dynamic>{
        'id': 'ev-2',
        'title': 'Meeting',
        'start': '2026-06-19T10:00:00.000',
        'color': '#3B82F6',
      };
      final event = CalendarEvent.fromJson(json);
      expect(event.color, 0xFF3B82F6);
    });

    test('copyWith updates fields', () {
      final event = CalendarEvent(
        id: 'ev-3',
        title: 'Old',
        start: DateTime(2026, 6, 19),
      );
      final updated = event.copyWith(title: 'New');
      expect(updated.title, 'New');
      expect(updated.id, event.id);
      expect(updated.start, event.start);
    });
  });
}
