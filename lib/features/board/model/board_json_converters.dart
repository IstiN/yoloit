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
