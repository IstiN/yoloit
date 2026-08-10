import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';

void main() {
  const plugin = ShapePlugin();

  test('metadata and initial state', () {
    expect(plugin.typeId, 'board.shape');
    expect(plugin.hasEditor, isTrue);
    expect(plugin.usePanelChrome, isFalse);
    expect(plugin.initialState['shape'], 'rectangle');
    expect(plugin.initialState['strokeWidth'], 3.0);
  });

  group('shapeColorsEqual', () {
    test('identical colors match', () {
      expect(shapeColorsEqual(Colors.red, Colors.red), isTrue);
      expect(
        shapeColorsEqual(const Color(0xFF93C5FD), const Color(0xFF93C5FD)),
        isTrue,
      );
    });

    test('any channel difference fails the comparison', () {
      const base = Color(0xFF102030);
      expect(shapeColorsEqual(base, const Color(0x00102030)), isFalse);
      expect(shapeColorsEqual(base, const Color(0xFF112030)), isFalse);
      expect(shapeColorsEqual(base, const Color(0xFF102130)), isFalse);
      expect(shapeColorsEqual(base, const Color(0xFF102031)), isFalse);
    });

    test('compares on rounded 8-bit channel values', () {
      expect(
        shapeColorsEqual(
          const Color.fromRGBO(16, 32, 48, 1.0),
          const Color(0xFF102030),
        ),
        isTrue,
      );
    });
  });

  group('panel content', () {
    Future<GlobalKey<_ShapeHostState>> pumpShape(
      WidgetTester tester,
      _ShapeHarness harness,
    ) async {
      final key = GlobalKey<_ShapeHostState>();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 300,
              height: 220,
              child: _ShapeHost(key: key, harness: harness),
            ),
          ),
        ),
      );
      await tester.pump();
      return key;
    }

    CustomPainter painterOf(WidgetTester tester) {
      final paint = tester.widget<CustomPaint>(
        find
            .ancestor(
              of: find.byType(TextField),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      return paint.painter!;
    }

    testWidgets('renders an editable text field over the shape', (
      tester,
    ) async {
      final harness = _ShapeHarness({...plugin.initialState, 'text': 'Hello'});
      await pumpShape(tester, harness);

      expect(find.text('Hello'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'World');
      await tester.pump();
      expect(harness.state['text'], 'World');
      // Other state keys are preserved by the merge.
      expect(harness.state['shape'], 'rectangle');
    });

    testWidgets('empty text shows a hint', (tester) async {
      await pumpShape(tester, _ShapeHarness({...plugin.initialState}));
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets('parses string numbers and vertical orientation', (
      tester,
    ) async {
      final harness = _ShapeHarness({
        ...plugin.initialState,
        'shape': 'CIRCLE',
        'strokeWidth': '4.5',
        'fontSize': '22',
        'textOrientation': 'vertical',
      });
      await pumpShape(tester, harness);

      expect(find.byType(RotatedBox), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders with an empty state using fallbacks', (tester) async {
      await pumpShape(tester, _ShapeHarness(const {}));
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
    });

    group('shouldRepaint', () {
      testWidgets('any painter property change triggers a repaint', (
        tester,
      ) async {
        final harness = _ShapeHarness({...plugin.initialState});
        final key = await pumpShape(tester, harness);
        final original = painterOf(tester);

        // Identical properties: no repaint needed.
        key.currentState!.updateState({...harness.state});
        await tester.pump();
        expect(painterOf(tester).shouldRepaint(original), isFalse);

        // Each individual property change must repaint.
        for (final change in [
          {'shape': 'circle'},
          {'fillColor': '#FF0000'},
          {'strokeColor': '#00FF00'},
          {'strokeWidth': 5.0},
        ]) {
          key.currentState!.updateState({...plugin.initialState, ...change});
          await tester.pump();
          expect(
            painterOf(tester).shouldRepaint(original),
            isTrue,
            reason: 'change $change should require a repaint',
          );
        }
      });
    });
  });
}

class _ShapeHarness {
  _ShapeHarness(this.state);

  Map<String, dynamic> state;
}

class _ShapeHost extends StatefulWidget {
  const _ShapeHost({super.key, required this.harness});

  final _ShapeHarness harness;

  @override
  State<_ShapeHost> createState() => _ShapeHostState();
}

class _ShapeHostState extends State<_ShapeHost> {
  void updateState(Map<String, dynamic> next) {
    setState(() => widget.harness.state = next);
  }

  @override
  Widget build(BuildContext context) {
    final panel = BoardPanelInstance(
      id: 'shape-1',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 220),
      state: widget.harness.state,
    );
    return const ShapePlugin().buildContent(
      context,
      panel,
      BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onShowEditor: () {},
        onUpdateState: updateState,
      ),
    );
  }
}
