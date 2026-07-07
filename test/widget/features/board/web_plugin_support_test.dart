// covers: board.ui, board.widget.custom (web-compatible rendering)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_capabilities.dart';
import 'package:yoloit/core/platform/platform_capabilities_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/custom_widget_plugin_content.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';

BoardPanelRenderContext _dummyContext({
  ValueChanged<Map<String, dynamic>>? onUpdateState,
}) => BoardPanelRenderContext(
  isSelected: false,
  onFocus: () {},
  onDelete: () {},
  onUpdateState: onUpdateState ?? (_) {},
  onShowEditor: () {},
);

BoardPanelInstance _panel(String typeId) => BoardPanelInstance(
  id: 'p1',
  type: typeId,
  title: 'Panel',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
  state: {},
);

void main() {
  group('Web capability support', () {
    setUp(() {
      PlatformCapabilities.current = const WebPlatformCapabilities();
    });

    tearDown(PlatformCapabilities.reset);

    testWidgets('UiViewPlugin is supported and renders on web', (
      tester,
    ) async {
      const plugin = UiViewPlugin();
      expect(plugin.isSupportedOnCurrentPlatform, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    _panel(UiViewPluginBase.kTypeId),
                    _dummyContext(),
                  ),
            ),
          ),
        ),
      );

      expect(find.text('UI View'), findsOneWidget);
      expect(find.text('Available in YoLoIT for macOS'), findsNothing);
    });

    testWidgets('CustomWidgetPlugin is supported and builds content on web', (
      tester,
    ) async {
      const plugin = CustomWidgetPlugin();
      expect(plugin.isSupportedOnCurrentPlatform, isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    _panel(CustomWidgetPlugin.kTypeId),
                    _dummyContext(),
                  ),
            ),
          ),
        ),
      );

      expect(find.byType(CustomWidgetContent), findsOneWidget);
      expect(find.text('Available in YoLoIT for macOS'), findsNothing);
    });
  });
}
