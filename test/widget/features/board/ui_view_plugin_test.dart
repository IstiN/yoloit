// covers: board.ui
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/ui_view_plugin_base.dart';

void main() {
  group('UiViewPlugin', () {
    const plugin = UiViewPlugin();

    testWidgets('renders default tree content', (tester) async {
      final panel = BoardPanelInstance(
        id: 'p1',
        type: UiViewPluginBase.kTypeId,
        title: 'UI',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
        state: {},
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    panel,
                    BoardPanelRenderContext(
                      isSelected: false,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (_) {},
                      onShowEditor: () {},
                    ),
                  ),
            ),
          ),
        ),
      );

      expect(find.text('UI View'), findsOneWidget);
      expect(find.text('Empty panel'), findsOneWidget);
    });

    testWidgets('editor dialog switches JSON / Preview / Scripts modes', (
      tester,
    ) async {
      final panel = BoardPanelInstance(
        id: 'p1',
        type: UiViewPluginBase.kTypeId,
        title: 'UI',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
        state: {},
      );

      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder:
                          (ctx) =>
                              plugin.buildEditorDialog(ctx, panel) as Widget,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('UI View — JSON tree'), findsOneWidget);

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('UI View'), findsOneWidget);

      await tester.tap(find.text('Scripts'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Нет кнопок с onTap в дереве. Добавьте в JSON:\n'
          '{"type":"button","data":"...","onTap":"myAction"}',
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(result, isNull);
    });

    testWidgets('editor applies parsed JSON state', (tester) async {
      final panel = BoardPanelInstance(
        id: 'p1',
        type: UiViewPluginBase.kTypeId,
        title: 'UI',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
        state: {},
      );

      Map<String, dynamic>? result;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<Map<String, dynamic>>(
                      context: context,
                      builder:
                          (ctx) =>
                              plugin.buildEditorDialog(ctx, panel) as Widget,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('JSON'));
      await tester.pumpAndSettle();

      final jsonField = find.byType(TextField).first;
      await tester.enterText(jsonField, '{"type":"text","data":"Hi"}');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Preview'));
      await tester.pumpAndSettle();
      expect(find.text('Hi'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!['tree'], {'type': 'text', 'data': 'Hi'});
    });

    testWidgets('editor Scripts mode lists button actions', (tester) async {
      final panel = BoardPanelInstance(
        id: 'p1',
        type: UiViewPluginBase.kTypeId,
        title: 'UI',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 240),
        state: {
          'tree': {
            'type': 'column',
            'children': [
              {'type': 'button', 'data': 'Tap me', 'onTap': 'doThing'},
            ],
          },
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    showDialog<void>(
                      context: context,
                      builder:
                          (ctx) =>
                              plugin.buildEditorDialog(ctx, panel) as Widget,
                    );
                  },
                  child: const Text('Open'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Scripts'));
      await tester.pumpAndSettle();

      expect(find.text('doThing'), findsOneWidget);
      expect(find.text('JavaScript для onTap: doThing'), findsOneWidget);
    });
  });
}
