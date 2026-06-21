import 'package:equatable/equatable.dart';
import 'package:yoloit/core/utils/color_utils.dart';

/// A single calendar event stored outside the board document.
///
/// Events are persisted as JSON in `<dataDir>/calendar_events/<panelId>.json`.
class CalendarEvent extends Equatable {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.start,
    this.end,
    this.allDay = false,
    this.description = '',
    this.color,
    this.meetingUrl,
  });

  final String id;
  final String title;
  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final String description;
  final int? color;
  final String? meetingUrl;

  bool get isMultiDay {
    final endTime = end;
    if (endTime == null) return false;
    return !_isSameDay(start, endTime);
  }

  DateTime get effectiveEnd => end ?? start;

  CalendarEvent copyWith({
    String? id,
    String? title,
    DateTime? start,
    DateTime? end,
    bool? allDay,
    String? description,
    int? color,
    String? meetingUrl,
  }) {
    return CalendarEvent(
      id: id ?? this.id,
      title: title ?? this.title,
      start: start ?? this.start,
      end: end ?? this.end,
      allDay: allDay ?? this.allDay,
      description: description ?? this.description,
      color: color ?? this.color,
      meetingUrl: meetingUrl ?? this.meetingUrl,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'start': start.toIso8601String(),
      if (end != null) 'end': end!.toIso8601String(),
      'allDay': allDay,
      'description': description,
      if (color != null) 'color': color,
      if (meetingUrl != null && meetingUrl!.isNotEmpty) 'meetingUrl': meetingUrl,
    };
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    final rawStart = json['start'];
    final rawEnd = json['end'];
    final rawColor = json['color'];
    return CalendarEvent(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      start: _parseDateTime(rawStart) ?? DateTime.now(),
      end: rawEnd == null ? null : _parseDateTime(rawEnd),
      allDay: json['allDay'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      color: rawColor == null ? null : _parseColorValue(rawColor),
      meetingUrl: json['meetingUrl'] as String?,
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value is DateTime) return value;
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    return null;
  }

  static int? _parseColorValue(dynamic value) {
    if (value is int) return value;
    if (value is String) {
      final color = parseColor(value);
      if (color != null) return color.toARGB32();
    }
    return null;
  }

  @override
  List<Object?> get props => [
    id,
    title,
    start,
    end,
    allDay,
    description,
    color,
    meetingUrl,
  ];
}

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
