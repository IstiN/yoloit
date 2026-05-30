import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  test('panel zIndex is copied and serialized for headless depth control', () {
    const panel = BoardPanelInstance(
      id: 'shape-1',
      type: 'board.shape',
      title: 'Shape',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 300, height: 200),
      zIndex: 3,
    );

    final front = panel.copyWith(zIndex: 9);
    expect(front.zIndex, 9);

    final json = front.toJson();
    expect(json['zIndex'], 9);

    final restored = BoardPanelInstance.fromJson(json);
    expect(restored.zIndex, 9);
  });
}
