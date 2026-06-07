import 'dart:math' as math;

import 'package:flutter/material.dart';

({TextEditingValue value, int start, int end, String selected})
    _selectionInfo(TextEditingController controller) {
  final value = controller.value;
  final selection =
      value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
  final start = math.min(selection.start, selection.end);
  final end = math.max(selection.start, selection.end);
  final selected = start < end ? value.text.substring(start, end) : '';
  return (value: value, start: start, end: end, selected: selected);
}

void wrapSelection(
  TextEditingController controller, {
  required String before,
  required String after,
  required String placeholder,
}) {
  final info = _selectionInfo(controller);
  final replacement =
      '$before${info.selected.isEmpty ? placeholder : info.selected}$after';
  final updated = info.value.text.replaceRange(info.start, info.end, replacement);
  final cursorOffset = info.start + replacement.length;
  controller.value = info.value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(offset: cursorOffset),
  );
}

void prefixSelectedLines(TextEditingController controller, String prefix) {
  final info = _selectionInfo(controller);
  final source = info.selected.isEmpty ? 'item' : info.selected;
  final replacement = source
      .split('\n')
      .map((line) => line.isEmpty ? prefix.trimRight() : '$prefix$line')
      .join('\n');
  final updated = info.value.text.replaceRange(info.start, info.end, replacement);
  controller.value = info.value.copyWith(
    text: updated,
    selection: TextSelection.collapsed(offset: info.start + replacement.length),
  );
}
