import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';
import 'package:yoloit/features/board/ui/panel_yolo_assistant_badge.dart';
import 'package:yoloit/features/board/ui/yolo_anchored_assistant_layout.dart';

void main() {
  const panel = BoardPanelInstance(
    id: 'shape',
    type: ShapePlugin.kTypeId,
    title: 'Effort',
    bounds: BoardPanelBounds(x: 0, y: 0, width: 320, height: 180),
    state: {'text': 'Effort ->'},
  );

  test('badge trigger is centered tab capped at preferred height', () {
    expect(
      YoloAnchoredAssistantLayout.triggerHeight(panel),
      120,
    );
    expect(
      YoloAnchoredAssistantLayout.badgeTopInCardWrapper(
        panel,
        selectionTopGutter: 62,
      ),
      92,
    );
  });

  test('small host panels keep minimum trigger height centered', () {
    const small = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Tiny',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 120, height: 60),
      state: const {},
    );
    expect(
      YoloAnchoredAssistantLayout.triggerHeight(small),
      PanelYoloAssistantBadge.minTriggerHeight,
    );
    expect(
      YoloAnchoredAssistantLayout.badgeTopInCardWrapper(
        small,
        selectionTopGutter: 62,
      ),
      48,
    );
  });
}
