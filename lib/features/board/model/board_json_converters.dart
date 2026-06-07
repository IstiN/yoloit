import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';

/// Serializes [Color] as a 32-bit ARGB integer.
class ColorJsonConverter implements JsonConverter<Color, int> {
  const ColorJsonConverter();

  @override
  Color fromJson(int json) => Color(json);

  @override
  int toJson(Color object) => object.toARGB32();
}

/// Serializes [Color?] as an optional 32-bit ARGB integer.
class ColorNullableJsonConverter implements JsonConverter<Color?, int?> {
  const ColorNullableJsonConverter();

  @override
  Color? fromJson(int? json) => json == null ? null : Color(json);

  @override
  int? toJson(Color? object) => object?.toARGB32();
}

/// Serializes [Offset] as a `[dx, dy]` array.
class OffsetJsonConverter implements JsonConverter<Offset, List<dynamic>> {
  const OffsetJsonConverter();

  @override
  Offset fromJson(List<dynamic> json) {
    final nums = json.cast<num>();
    return Offset(nums[0].toDouble(), nums[1].toDouble());
  }

  @override
  List<double> toJson(Offset object) => [object.dx, object.dy];
}

/// Serializes [Size] as a `[width, height]` array.
class SizeJsonConverter implements JsonConverter<Size, List<dynamic>> {
  const SizeJsonConverter();

  @override
  Size fromJson(List<dynamic> json) {
    final nums = json.cast<num>();
    return Size(nums[0].toDouble(), nums[1].toDouble());
  }

  @override
  List<double> toJson(Size object) => [object.width, object.height];
}

/// Serializes [Map<String, Offset>] as a JSON object where each value
/// is a `[dx, dy]` array.
class OffsetMapJsonConverter
    implements JsonConverter<Map<String, Offset>, Map<String, List<double>>> {
  const OffsetMapJsonConverter();

  @override
  Map<String, Offset> fromJson(Map<String, List<double>> json) =>
      json.map(
        (k, v) => MapEntry(k, Offset(v[0], v[1])),
      );

  @override
  Map<String, List<double>> toJson(Map<String, Offset> object) =>
      object.map((k, v) => MapEntry(k, [v.dx, v.dy]));
}

/// Serializes [Map<String, Size>] as a JSON object where each value
/// is a `[width, height]` array.
class SizeMapJsonConverter
    implements JsonConverter<Map<String, Size>, Map<String, List<double>>> {
  const SizeMapJsonConverter();

  @override
  Map<String, Size> fromJson(Map<String, List<double>> json) =>
      json.map(
        (k, v) => MapEntry(k, Size(v[0], v[1])),
      );

  @override
  Map<String, List<double>> toJson(Map<String, Size> object) =>
      object.map((k, v) => MapEntry(k, [v.width, v.height]));
}

/// Serializes [Set<String>] as a JSON array of strings.
class StringSetJsonConverter implements JsonConverter<Set<String>, List<String>> {
  const StringSetJsonConverter();

  @override
  Set<String> fromJson(List<String> json) => json.toSet();

  @override
  List<String> toJson(Set<String> object) => object.toList();
}

/// Serializes [Color] as an 8-character hex string (e.g. 'ff7c3aed').
class ColorHexJsonConverter implements JsonConverter<Color, String> {
  const ColorHexJsonConverter();

  @override
  Color fromJson(String json) {
    final h = json.replaceFirst('#', '');
    if (h.length == 6) return Color(int.parse('FF$h', radix: 16));
    return Color(int.parse(h, radix: 16));
  }

  @override
  String toJson(Color object) =>
      object.value.toRadixString(16).padLeft(8, '0');
}
