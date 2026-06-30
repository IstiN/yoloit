import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/ui/board_view.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

void main() {
  setUp(() {
    CanvasInteractionLock.instance.resetForTesting();
  });

  tearDown(() {
    CanvasInteractionLock.instance.resetForTesting();
  });

  group('boardShouldRevertInteractionForCanvasLock', () {
    test(
      'does not revert a canvas pan when lock appears after gesture start',
      () {
        expect(
          boardShouldRevertInteractionForCanvasLock(
            interactionStartedLocked: false,
            currentlyLocked: true,
          ),
          isFalse,
        );
      },
    );

    test('reverts gestures that started while canvas was locked', () {
      expect(
        boardShouldRevertInteractionForCanvasLock(
          interactionStartedLocked: true,
          currentlyLocked: true,
        ),
        isTrue,
      );
    });

    test('does not revert a locked interaction once pinch scale changes', () {
      expect(
        boardShouldRevertInteractionForCanvasLock(
          interactionStartedLocked: true,
          currentlyLocked: true,
          isScaleChanging: true,
        ),
        isFalse,
      );
    });
  });

  group('CanvasInteractionLock', () {
    test('canvas gesture temporarily wins over scrollable hover lock', () {
      CanvasInteractionLock.instance.enter();
      expect(CanvasInteractionLock.instance.isLocked, isTrue);

      CanvasInteractionLock.instance.beginCanvasGesture();
      expect(CanvasInteractionLock.instance.activeCount.value, 1);
      expect(CanvasInteractionLock.instance.isCanvasGestureActive, isTrue);
      expect(CanvasInteractionLock.instance.isLocked, isFalse);

      CanvasInteractionLock.instance.endCanvasGesture();
      expect(CanvasInteractionLock.instance.isCanvasGestureActive, isFalse);
      expect(CanvasInteractionLock.instance.isLocked, isTrue);
    });

    testWidgets(
      'scrollable regions do not lock canvas during a canvas-owned gesture',
      (tester) async {
        CanvasInteractionLock.instance.beginCanvasGesture();

        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 120,
                child: ScrollableCardRegion(
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final center = tester.getCenter(find.byType(ScrollableCardRegion));
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(pointer: 1, position: center),
        );
        await tester.sendEventToBinding(
          PointerPanZoomUpdateEvent(
            pointer: 1,
            position: center,
            panDelta: const Offset(0, 80),
          ),
        );
        await tester.pump();

        expect(CanvasInteractionLock.instance.activeCount.value, 0);

        CanvasInteractionLock.instance.endCanvasGesture();
      },
    );

    testWidgets(
      'releases lock after pan-zoom ends outside the scrollable region',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 200,
                height: 120,
                child: ScrollableCardRegion(
                  child: ColoredBox(color: Colors.red),
                ),
              ),
            ),
          ),
        );
        await tester.pump();

        final center = tester.getCenter(find.byType(ScrollableCardRegion));
        await tester.sendEventToBinding(
          PointerPanZoomStartEvent(pointer: 1, position: center),
        );
        await tester.pump();
        expect(CanvasInteractionLock.instance.activeCount.value, 1);

        await tester.sendEventToBinding(
          PointerPanZoomEndEvent(
            pointer: 1,
            position: center + const Offset(400, 400),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));

        expect(CanvasInteractionLock.instance.activeCount.value, 0);
      },
    );
  });
}
