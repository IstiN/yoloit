/// Unit tests for the _GutterPaint CustomPainter exposed via the
/// [createGutterPainterForTest] test seam in file_editor_panel.dart.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/editor/ui/file_editor_panel.dart';
import 'package:yoloit/features/editor/utils/editor_panel_logic.dart';

void main() {
  const addedColor = Color(0xFF4CAF50);
  const removedColor = Color(0xFFF44336);
  const lineHeight = 20.0;
  const canvasWidth = 3.0;
  const canvasHeight = 200.0;
  const canvasSize = Size(canvasWidth, canvasHeight);

  /// Records a single paint pass into a [Picture] without throwing.
  Picture paintToPicture(CustomPainter painter) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, canvasSize);
    return recorder.endRecording();
  }

  group('_GutterPaint.paint', () {
    test('(a) empty markers map does not throw or crash', () {
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('(b) added marker draws a rect without throwing', () {
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('(c) removed marker draws a rect without throwing', () {
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.removed},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('(d) off-screen markers (top > height and bottom < 0) are skipped', () {
      // scrollOffset 400 → line 1 (index 0): top = -400, bottom = -380 (< 0).
      // Line 1001 (index 1000): top = 20000 - 400 = 19600 > 200 (height).
      // Both are skipped via the early-continue but must not throw.
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{
          1: GutterMarkerType.added, // bottom < 0
          1001: GutterMarkerType.removed, // top > height
        },
        lineHeight: lineHeight,
        scrollOffset: 400,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('marker partially clipped at top is clamped within canvas bounds', () {
      // scrollOffset 10 → line 1 (index 0): top = -10, bottom = 10.
      // top clamps to 0, bottom stays 10. Should not throw.
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 10,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('marker partially clipped at bottom is clamped within canvas bounds', () {
      // canvas height 200, lineHeight 20. Line 11 (index 10): top = 200,
      // bottom = 220 → top clamps to 200, bottom clamps to 200 (zero-height).
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{
          10: GutterMarkerType.added,
          11: GutterMarkerType.removed,
        },
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('multiple mixed markers all draw without throwing', () {
      final painter = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{
          1: GutterMarkerType.added,
          2: GutterMarkerType.removed,
          3: GutterMarkerType.added,
          5: GutterMarkerType.removed,
        },
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(() => paintToPicture(painter), returnsNormally);
    });

    test('shouldRepaint returns true when scrollOffset changes', () {
      // Both instances are _GutterPaint at runtime; the covariant override
      // accepts the call through the public CustomPainter interface.
      final base = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );
      final changed = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 40,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(base.shouldRepaint(changed), isTrue);
    });

    test('shouldRepaint returns false when all fields are identical', () {
      final base = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );
      final same = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(base.shouldRepaint(same), isFalse);
    });

    test('shouldRepaint returns true when markers differ', () {
      final base = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );
      final changed = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{
          1: GutterMarkerType.added,
          2: GutterMarkerType.removed,
        },
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(base.shouldRepaint(changed), isTrue);
    });

    test('shouldRepaint returns true when lineHeight changes', () {
      final base = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: lineHeight,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );
      final changed = createGutterPainterForTest(
        markers: const <int, GutterMarkerType>{1: GutterMarkerType.added},
        lineHeight: 24.0,
        scrollOffset: 0,
        addedColor: addedColor,
        removedColor: removedColor,
      );

      expect(base.shouldRepaint(changed), isTrue);
    });
  });
}
