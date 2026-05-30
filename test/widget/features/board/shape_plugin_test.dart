import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';

void main() {
  const plugin = ShapePlugin();

  test('shape uses Miro-style chrome and transparent fill by default', () {
    expect(plugin.usePanelChrome, isFalse);
    expect(plugin.showHeader, isFalse);
    expect(plugin.hasEditor, isTrue);
    expect(plugin.initialState['fillColor'], '#00000000');
    expect(plugin.initialState['textHAlign'], 'center');
    expect(plugin.initialState['textVAlign'], 'center');
    expect(plugin.initialState['textOrientation'], 'horizontal');
  });

  testWidgets('shape edits label inline', (tester) async {
    var state = <String, dynamic>{...plugin.initialState, 'text': 'Initial'};
    final panel = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 220),
      state: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 220,
            child: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    panel,
                    BoardPanelRenderContext(
                      isSelected: true,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (nextState) => state = nextState,
                      onShowEditor: () {},
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'Updated shape');
    expect(state['text'], 'Updated shape');
  });

  testWidgets('shape shows selected variant palette', (tester) async {
    var state = <String, dynamic>{...plugin.initialState};
    final panel = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 220),
      state: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 220,
            child: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    panel,
                    BoardPanelRenderContext(
                      isSelected: true,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (nextState) => state = nextState,
                      onShowEditor: () {},
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('○'), findsOneWidget);
    expect(find.text('◇'), findsOneWidget);

    await tester.tap(find.text('◇'));
    expect(state['shape'], 'diamond');
  });

  testWidgets('shape palette updates color and text placement', (tester) async {
    var state = <String, dynamic>{...plugin.initialState};
    final panel = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 260),
      state: state,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            height: 260,
            child: Builder(
              builder:
                  (context) => plugin.buildContent(
                    context,
                    panel,
                    BoardPanelRenderContext(
                      isSelected: true,
                      onFocus: () {},
                      onDelete: () {},
                      onUpdateState: (nextState) => state = nextState,
                      onShowEditor: () {},
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('Color #FBBF24'));
    expect(state['strokeColor'], '#FBBF24');
    expect(state['textColor'], '#FBBF24');

    await tester.tap(find.text('R'));
    expect(state['textHAlign'], 'right');

    await tester.tap(find.text('B'));
    expect(state['textVAlign'], 'bottom');

    await tester.tap(find.text('V'));
    expect(state['textOrientation'], 'vertical');
  });

  testWidgets('shape editor applies grouped settings as JSON state', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Map<String, dynamic>? saved;
    final panel = BoardPanelInstance(
      id: 'shape',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 260),
      state: {...plugin.initialState},
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder:
                (context) => TextButton(
                  onPressed: () {
                    plugin.showEditor(context, panel, (state) => saved = state);
                  },
                  child: const Text('Open editor'),
                ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.text('Shape settings'), findsOneWidget);
    await tester.tap(find.text('Diamond'));
    await tester.tap(find.text('Right'));
    await tester.tap(find.text('Bottom'));
    await tester.tap(find.text('Vertical'));
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!['shape'], 'diamond');
    expect(saved!['textHAlign'], 'right');
    expect(saved!['textVAlign'], 'bottom');
    expect(saved!['textOrientation'], 'vertical');
    expect(saved!.keys, containsAll(['fillColor', 'strokeColor', 'textColor']));
  });
}
