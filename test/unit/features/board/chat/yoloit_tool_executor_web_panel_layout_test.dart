import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../../helpers/fake_board_cubit.dart';

BoardPanelInstance _panel(
  String id,
  String title, {
  int zIndex = 0,
}) {
  return BoardPanelInstance(
    id: id,
    type: 'board.note.markdown',
    title: title,
    bounds: const BoardPanelBounds(x: 10, y: 20, width: 500, height: 350),
    zIndex: zIndex,
  );
}

void main() {
  group('YoloitWebToolExecutor panel layout handlers', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
      cubit.addFakePanel(_panel('p-target', 'Target', zIndex: 2));
      cubit.addFakePanel(_panel('p-other', 'Other', zIndex: 9));
    });

    tearDown(() => cubit.close());

    Future<Map<String, dynamic>> invoke(
      String name,
      Map<String, Object?> args,
    ) async {
      final result = await executor.invoke(
        name,
        args,
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      return jsonDecode(result) as Map<String, dynamic>;
    }

    test('panel:resize supports every named preset', () async {
      const presets = <String, (double, double)>{
        'small': (420, 300),
        'medium': (720, 480),
        'desktop': (1200, 800),
        'large': (1400, 900),
        'mobile': (390, 844),
        'tablet': (768, 1024),
      };

      for (final preset in presets.entries) {
        final result = await invoke('yoloit_panel_resize', <String, Object?>{
          'panel': 'Target',
          'width': preset.key,
        });
        expect(result['ok'], isTrue, reason: preset.key);
        final bounds = cubit.updatedPanels['p-target']!.bounds;
        expect(bounds.width, preset.value.$1, reason: preset.key);
        expect(bounds.height, preset.value.$2, reason: preset.key);
      }
    });

    test('panel:resize accepts explicit dimensions and aliases', () async {
      final explicit = await invoke('yoloit_panel_resize', <String, Object?>{
        'panel': 'p-target',
        'width': 850,
        'height': 620,
      });
      expect(explicit['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.bounds.width, 850);
      expect(cubit.updatedPanels['p-target']!.bounds.height, 620);

      final aliases = await invoke('yoloit_panel_resize', <String, Object?>{
        'panel': 'p-target',
        'w': '910',
        'h': '640',
      });
      expect(aliases['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.bounds.width, 910);
      expect(cubit.updatedPanels['p-target']!.bounds.height, 640);
    });

    test('panel:resize keeps existing dimensions when none are supplied', () async {
      final result = await invoke('yoloit_panel_resize', <String, Object?>{
        'panel': 'p-target',
      });

      expect(result['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.bounds.width, 500);
      expect(cubit.updatedPanels['p-target']!.bounds.height, 350);
    });

    test('panel:z moves a panel to front, back, or an explicit index', () async {
      final front = await invoke('yoloit_panel_z', <String, Object?>{
        'panel': 'Target',
        'front_or_back_or_zindex': 'front',
      });
      expect(front['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.zIndex, 10);

      final back = await invoke('yoloit_panel_z', <String, Object?>{
        'panel': 'Target',
        'z': 'back',
      });
      expect(back['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.zIndex, 0);

      final numeric = await invoke('yoloit_panel_z', <String, Object?>{
        'panel': 'Target',
        'z': 7,
      });
      expect(numeric['ok'], isTrue);
      expect(cubit.updatedPanels['p-target']!.zIndex, 7);
    });

    test('panel:z rejects invalid values without changing the panel', () async {
      final result = await invoke('yoloit_panel_z', <String, Object?>{
        'panel': 'Target',
        'z': 'sideways',
      });

      expect(result['ok'], isFalse);
      expect(result['error'], contains('Invalid z value'));
      expect(cubit.updatedPanels, isNot(contains('p-target')));
    });
  });
}
