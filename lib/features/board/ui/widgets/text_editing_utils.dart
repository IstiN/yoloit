import 'dart:math' as math;

import 'package:flutter/material.dart';

void wrapSelection(
  TextEditingController controller, {
  required String before,
  required String after,
  required String placeholder,
}) {
  final value = controller.value;
  final selection =
      value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
  final start = math.min(selection.start, selection.end);
  final end = math.max(selection.start, selection.end);
  final selected = start < end ? value.text.substring(start, end) : '';
  final replacement =
      '$before${selected.isEmpty ? placeholder : selected}$after';
  final updated = value.text.replaceRange(start, end, replacement);
  final cursorOffset = start + replacement.length;
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(offset: cursorOffset),
  );
}

void prefixSelectedLines(TextEditingController controller, String prefix) {
  final value = controller.value;
  final selection =
      value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
  final start = math.min(selection.start, selection.end);
  final end = math.max(selection.start, selection.end);
  final block = start < end ? value.text.substring(start, end) : '';
  final source = block.isEmpty ? 'item' : block;
  final replacement = source
      .split('\n')
      .map((line) => line.isEmpty ? prefix.trimRight() : '$prefix$line')
      .join('\n');
  final updated = value.text.replaceRange(start, end, replacement);
  controller.value = value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}
