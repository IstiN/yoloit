import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/mindmap/widgets/canvas_interaction_lock.dart';

void main() {
  group('PanelScrollLockBehavior', () {
    testWidgets(
      'wraps scrollables inside a ScrollableCardRegion',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ScrollConfiguration(
              behavior: const PanelScrollLockBehavior(),
              child: SizedBox(
                height: 200,
                child: ListView(
                  children: const [SizedBox(height: 400, child: Text('item'))],
                ),
              ),
            ),
          ),
        );

        expect(find.byType(ScrollableCardRegion), findsOneWidget);
      },
    );
  });

  group('ScrollableCardRegion', () {
    setUp(() {
      CanvasInteractionLock.instance.resetForTesting();
    });

    tearDown(() {
      CanvasInteractionLock.instance.resetForTesting();
    });

    testWidgets(
      'enters canvas lock while pointer is over the region and releases on exit',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 200,
                height: 200,
                child: ScrollableCardRegion(
                  child: Container(color: Colors.red),
                ),
              ),
            ),
          ),
        );

        expect(CanvasInteractionLock.instance.isLocked, isFalse);

        final center = tester.getCenter(find.byType(Container));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.down(center));
        await tester.pump();

        expect(CanvasInteractionLock.instance.isLocked, isTrue);

        await tester.sendEventToBinding(pointer.up());
        await tester.sendEventToBinding(
          pointer.hover(const Offset(-10, -10)),
        );
        await tester.pump(const Duration(milliseconds: 150));

        expect(CanvasInteractionLock.instance.isLocked, isFalse);
      },
    );

    testWidgets(
      'keeps canvas locked during a pointer scroll event over the region',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ColoredBox(
              color: Colors.white,
              child: SizedBox(
                width: 200,
                height: 200,
                child: ScrollableCardRegion(
                  child: Container(color: Colors.blue),
                ),
              ),
            ),
          ),
        );

        final center = tester.getCenter(find.byType(Container));
        final pointer = TestPointer(1, PointerDeviceKind.mouse);
        await tester.sendEventToBinding(pointer.hover(center));
        await tester.pump();
        expect(CanvasInteractionLock.instance.isLocked, isTrue);

        await tester.sendEventToBinding(
          pointer.scroll(const Offset(0, 10)),
        );
        await tester.pump();

        expect(CanvasInteractionLock.instance.isLocked, isTrue);

        await tester.sendEventToBinding(
          pointer.hover(const Offset(-10, -10)),
        );
        await tester.pump(const Duration(milliseconds: 150));
        expect(CanvasInteractionLock.instance.isLocked, isFalse);
      },
    );
  });
}
