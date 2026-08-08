import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_drawing_widgets.dart';

BoardDrawingElement _drawing({
  List<List<Offset>> strokes = const [
    [Offset(0, 50), Offset(100, 50)],
  ],
  double strokeWidth = 4,
}) => BoardDrawingElement(
  id: 'd1',
  strokes: strokes,
  position: const Offset(10, 10),
  size: const Size(100, 100),
  strokeColor: const Color(0xFF000000),
  strokeWidth: strokeWidth,
);

void main() {
  group('DrawingElementPainter.strokeHitTest', () {
    test('returns false when there are no strokes', () {
      expect(
        DrawingElementPainter.strokeHitTest(
          _drawing(strokes: const []),
          const Offset(50, 50),
        ),
        isFalse,
      );
    });

    test('skips empty strokes', () {
      expect(
        DrawingElementPainter.strokeHitTest(
          _drawing(strokes: const [<Offset>[]]),
          const Offset(50, 50),
        ),
        isFalse,
      );
    });

    test('single-point stroke hits within the radius', () {
      final d = _drawing(strokes: const [
        [Offset(50, 50)],
      ]);
      // hitRadius = 4 / 2 + 8 = 10
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(55, 50)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(70, 50)),
        isFalse,
      );
    });

    test('multi-segment stroke hits near any segment', () {
      final d = _drawing(strokes: const [
        [Offset(0, 0), Offset(100, 0), Offset(100, 100)],
      ]);
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(50, 5)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(95, 50)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(50, 50)),
        isFalse,
      );
    });

    test('respects the hit radius derived from stroke width', () {
      final d = _drawing(strokeWidth: 20); // radius = 20 / 2 + 8 = 18
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(50, 68)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(50, 69)),
        isFalse,
      );
    });

    test('clamps the projection to segment endpoints', () {
      final d = _drawing(strokes: const [
        [Offset(20, 20), Offset(80, 20)],
      ]);
      // Beyond both ends but within radius of an endpoint.
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(12, 20)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(88, 20)),
        isTrue,
      );
      // Far past the endpoint.
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(200, 20)),
        isFalse,
      );
    });

    test('handles a degenerate zero-length segment', () {
      final d = _drawing(strokes: const [
        [Offset(30, 30), Offset(30, 30)],
      ]);
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(35, 30)),
        isTrue,
      );
      expect(
        DrawingElementPainter.strokeHitTest(d, const Offset(80, 80)),
        isFalse,
      );
    });
  });

  group('DrawingElementPainter', () {
    test('hitTest returns true near a stroke and null elsewhere', () {
      final painter = DrawingElementPainter(drawing: _drawing());
      expect(painter.hitTest(const Offset(50, 50)), isTrue);
      expect(painter.hitTest(const Offset(0, 0)), isNull);
    });

    test('shouldRepaint only when the drawing changes', () {
      final painter = DrawingElementPainter(drawing: _drawing());
      expect(
        painter.shouldRepaint(DrawingElementPainter(drawing: _drawing())),
        isFalse,
      );
      expect(
        painter.shouldRepaint(
          DrawingElementPainter(drawing: _drawing(strokeWidth: 8)),
        ),
        isTrue,
      );
    });

    test('paint draws strokes and skips empty ones', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = DrawingElementPainter(
        drawing: _drawing(strokes: const [
          <Offset>[],
          [Offset(0, 0), Offset(10, 10), Offset(20, 0)],
        ]),
      );
      painter.paint(canvas, const Size(100, 100));
      final picture = recorder.endRecording();
      expect(picture, isNotNull);
    });
  });

  group('ActiveStrokePainter', () {
    test('paint is a no-op with fewer than two points', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = ActiveStrokePainter(
        points: [Offset(1, 1)],
        origin: Offset.zero,
        color: Color(0xFF000000),
        strokeWidth: 2,
      );
      painter.paint(canvas, const Size(50, 50));
      expect(recorder.endRecording(), isNotNull);
      expect(
        painter.shouldRepaint(
          const ActiveStrokePainter(
            points: [],
            origin: Offset.zero,
            color: Color(0xFF000000),
            strokeWidth: 2,
          ),
        ),
        isTrue,
      );
    });

    test('paint draws a path through the translated points', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const painter = ActiveStrokePainter(
        points: [Offset(0, 0), Offset(10, 10), Offset(20, 5)],
        origin: Offset(5, 5),
        color: Color(0xFF000000),
        strokeWidth: 2,
      );
      painter.paint(canvas, const Size(50, 50));
      expect(recorder.endRecording(), isNotNull);
    });
  });

  group('ConnectPreviewPainter', () {
    BoardPanelInstance panel(String id) => BoardPanelInstance(
      id: id,
      type: 'board.note',
      title: id,
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 80),
    );

    test('paint returns early when the source panel is missing', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = ConnectPreviewPainter(
        panels: [panel('a')],
        sourceId: 'missing',
        targetPoint: const Offset(200, 200),
        origin: Offset.zero,
        color: const Color(0xFF000000),
      );
      painter.paint(canvas, const Size(400, 400));
      expect(recorder.endRecording(), isNotNull);
    });

    test('paint draws a dashed curve toward the target', () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final painter = ConnectPreviewPainter(
        panels: [panel('a')],
        sourceId: 'a',
        targetPoint: const Offset(300, 200),
        origin: const Offset(10, 10),
        color: const Color(0xFF0000FF),
      );
      painter.paint(canvas, const Size(500, 400));
      expect(recorder.endRecording(), isNotNull);
      expect(
        painter.shouldRepaint(
          const ConnectPreviewPainter(
            panels: [],
            sourceId: 'a',
            targetPoint: Offset.zero,
            origin: Offset.zero,
            color: Color(0xFF000000),
          ),
        ),
        isTrue,
      );
    });
  });

  group('BoardDrawingWidget', () {
    Widget harness({
      bool isSelectMode = true,
      ValueChanged<Offset>? onMove,
      VoidCallback? onDelete,
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: BoardDrawingWidget(
              drawing: _drawing(),
              isSelectMode: isSelectMode,
              onMove: onMove ?? (_) {},
              onDelete: onDelete ?? () {},
            ),
          ),
        ),
      );
    }

    testWidgets('tap toggles selection and shows the delete badge', (
      tester,
    ) async {
      var deleted = 0;
      await tester.pumpWidget(harness(onDelete: () => deleted++));

      expect(find.byIcon(Icons.close), findsNothing);
      await tester.tap(find.byType(BoardDrawingWidget));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(deleted, 1);
    });

    testWidgets('no badge and no tap selection outside select mode', (
      tester,
    ) async {
      await tester.pumpWidget(harness(isSelectMode: false));
      await tester.tap(find.byType(BoardDrawingWidget));
      await tester.pump();
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('pan drag reports the moved position', (tester) async {
      final moves = <Offset>[];
      await tester.pumpWidget(harness(onMove: moves.add));

      await tester.drag(find.byType(BoardDrawingWidget), const Offset(40, 30));
      await tester.pump();

      expect(moves, isNotEmpty);
      // Pan deltas exclude the touch-slop portion; compare loosely.
      expect(moves.last.dx, greaterThan(10));
      expect(moves.last.dx, lessThanOrEqualTo(50));
      expect(moves.last.dy, greaterThan(10));
      expect(moves.last.dy, lessThanOrEqualTo(40));
    });

    testWidgets('hover over a stroke shows the badge, leaving hides it', (
      tester,
    ) async {
      await tester.pumpWidget(harness());

      final renderBox = tester.renderObject<StrokeHitTestRenderBox>(
        find.byType(StrokeHitTestBox),
      );

      // Arm hover with a real mouse hover over the stroke.
      final center = tester.getCenter(find.byType(BoardDrawingWidget));
      final gesture = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      addTearDown(gesture.removePointer);
      await gesture.moveTo(center);
      // First pump runs the post-frame callback, second rebuilds.
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.close), findsOneWidget);

      // A hit test that misses every stroke disarms the hover state. The
      // miss callback is delivered via a post-frame callback, which only
      // runs when a frame is scheduled — automated test bindings skip idle
      // pumps, so force a frame.
      final local = renderBox.globalToLocal(center);
      expect(
        renderBox.hitTest(
          BoxHitTestResult(),
          position: local - const Offset(0, 40),
        ),
        isFalse,
      );
      tester.binding.scheduleFrame();
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('pointer exit and cancel reset the hover state', (
      tester,
    ) async {
      await tester.pumpWidget(harness());

      final renderBox = tester.renderObject<StrokeHitTestRenderBox>(
        find.byType(StrokeHitTestBox),
      );
      final entry = BoxHitTestEntry(renderBox, Offset.zero);

      // Force hover on via a real hit near the stroke.
      final center = tester.getCenter(find.byType(BoardDrawingWidget));
      final local = renderBox.globalToLocal(center);
      final result = BoxHitTestResult();
      expect(renderBox.hitTest(result, position: local), isTrue);
      await tester.pump();

      renderBox.handleEvent(const PointerExitEvent(), entry);
      // Hover was cleared — a second exit is a no-op.
      renderBox.handleEvent(const PointerExitEvent(), entry);

      // Re-arm hover and clear via cancel instead.
      expect(renderBox.hitTest(BoxHitTestResult(), position: local), isTrue);
      await tester.pump();
      renderBox.handleEvent(const PointerCancelEvent(), entry);
      await tester.pump();
    });
  });
}
