import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_math.dart';

void main() {
  group('matrixScaleOf', () {
    test('returns 1.0 for identity matrix', () {
      final m = Matrix4.identity();
      expect(matrixScaleOf(m), closeTo(1.0, 0.0001));
    });

    test('returns 2.0 for uniform scale of 2', () {
      final m = Matrix4.identity()..scale(2.0);
      expect(matrixScaleOf(m), closeTo(2.0, 0.0001));
    });

    test('returns 0.5 for uniform scale of 0.5', () {
      final m = Matrix4.identity()..scale(0.5);
      expect(matrixScaleOf(m), closeTo(0.5, 0.0001));
    });

    test('reads first column magnitude (x-axis scale)', () {
      final m = Matrix4.identity()..scale(3.0, 4.0);
      // matrixScaleOf looks at the first column, so it reports the x-scale.
      expect(matrixScaleOf(m), closeTo(3.0, 0.0001));
    });
  });

  group('linkMidpoint', () {
    const start = Offset(0, 0);
    const end = Offset(100, 100);

    test('straight geometry returns centre of line', () {
      final mid = linkMidpoint(start, end, BoardLinkGeometry.straight);
      expect(mid, const Offset(50, 50));
    });

    test('elbow geometry returns corner at (end.dx, start.dy)', () {
      final mid = linkMidpoint(start, end, BoardLinkGeometry.elbow);
      expect(mid, const Offset(100, 0));
    });

    test('bezier geometry samples cubic curve at t=0.5', () {
      final mid = linkMidpoint(start, end, BoardLinkGeometry.bezier);
      // Cubic Bezier with horizontal control points at 35% should produce
      // a midpoint close to the geometric centre for this symmetric case.
      expect(mid.dx, closeTo(50, 0.1));
      expect(mid.dy, closeTo(50, 0.1));
    });

    test('bezier with vertical offset produces y between start and end', () {
      final mid = linkMidpoint(
        const Offset(0, 0),
        const Offset(200, 0),
        BoardLinkGeometry.bezier,
      );
      expect(mid.dx, closeTo(100, 0.1));
      expect(mid.dy, closeTo(0, 0.1));
    });
  });

  group('formatters', () {
    test('fmtDouble limits to two decimals', () {
      expect(fmtDouble(math.pi), '3.14');
      expect(fmtDouble(1.0), '1.00');
      expect(fmtDouble(0.005), '0.01');
    });

    test('fmtOffset produces parenthesised coordinates', () {
      expect(fmtOffset(const Offset(12.345, -67.89)), '(12.35, -67.89)');
    });

    test('fmtSize produces WxH string', () {
      expect(fmtSize(const Size(320, 240)), '320.00x240.00');
    });

    test('fmtRect lists edges in l/t/r/b order', () {
      final rect = Rect.fromLTRB(10.5, 20.5, 110.5, 220.5);
      expect(
        fmtRect(rect),
        'l=10.50 t=20.50 r=110.50 b=220.50',
      );
    });

    test('fmtMatrix reports scale and translation', () {
      final m = Matrix4.identity()
        ..scale(2.5)
        ..setTranslationRaw(100.0, 200.0, 0.0);
      final formatted = fmtMatrix(m);
      expect(formatted, contains('scale=2.50'));
      expect(formatted, contains('t=(100.00, 200.00)'));
    });
  });
}
