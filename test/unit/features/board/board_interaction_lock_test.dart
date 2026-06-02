import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

void main() {
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
  });
}
