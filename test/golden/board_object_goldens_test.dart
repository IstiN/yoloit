import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:golden_toolkit/golden_toolkit.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/shape_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';
import 'package:yoloit/features/board/ui/board_view.dart';

BoardPanelRenderContext _noopContext({bool selected = false}) {
  return BoardPanelRenderContext(
    isSelected: selected,
    onFocus: () {},
    onDelete: () {},
    onUpdateState: (_) {},
    onShowEditor: () {},
  );
}

Widget _pluginShell({
  required Widget Function(BuildContext context) builder,
  Size size = const Size(520, 360),
}) {
  return MaterialApp(
    key: const ValueKey('board-chrome-app'),
    theme: AppThemePreset.neonPurple.theme,
    home: Scaffold(
      backgroundColor: const Color(0xFF10131C),
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: Builder(builder: builder),
        ),
      ),
    ),
  );
}

BoardPanelInstance _shapePanel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'shape_golden',
      type: ShapePlugin.kTypeId,
      title: 'Shape',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 420, height: 260),
      state: {...const ShapePlugin().initialState, ...state},
    );

BoardPanelInstance _stickyPanel({Map<String, dynamic> state = const {}}) =>
    BoardPanelInstance(
      id: 'sticky_golden',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 260, height: 220),
      state: {...const StickyNotePlugin().initialState, ...state},
    );

BoardPanelInstance _standardPanel() {
  return const BoardPanelInstance(
    id: 'note_panel',
    type: MarkdownNotePlugin.kTypeId,
    title: 'Weather — Spitalfields',
    bounds: BoardPanelBounds(x: 56, y: 74, width: 520, height: 300),
    zIndex: 7,
    state: {'markdown': '## Partly cloudy'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Golden tests — Board Miro objects', () {
    testGoldens('shape selected toolbar', (tester) async {
      await tester.pumpWidgetBuilder(
        _pluginShell(
          builder:
              (context) => const ShapePlugin().buildContent(
                context,
                _shapePanel(state: {'text': 'Decision', 'shape': 'diamond'}),
                _noopContext(selected: true),
              ),
        ),
        surfaceSize: const Size(520, 360),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'board_shape_selected_toolbar');
    });

    testGoldens('sticky note appearance', (tester) async {
      await tester.pumpWidgetBuilder(
        _pluginShell(
          size: const Size(360, 300),
          builder:
              (context) => const StickyNotePlugin().buildContent(
                context,
                _stickyPanel(
                  state: {
                    'text': 'Plan release\nShip shapes',
                    'color': '#FDE68A',
                    'textColor': '#111827',
                    'fontSize': 22.0,
                  },
                ),
                _noopContext(selected: true),
              ),
        ),
        surfaceSize: const Size(360, 300),
      );
      await tester.pump();
      await screenMatchesGolden(tester, 'board_sticky_note');
    });

    testGoldens('shape grouped editor dialog', (tester) async {
      await tester.pumpWidgetBuilder(
        _pluginShell(
          size: const Size(680, 720),
          builder:
              (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    const ShapePlugin().showEditor(
                      context,
                      _shapePanel(),
                      (_) {},
                    );
                  },
                  child: const Text('Open editor'),
                ),
              ),
        ),
        surfaceSize: const Size(680, 720),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await screenMatchesGolden(tester, 'board_shape_editor_dialog');
    });

    testGoldens('sticky grouped editor dialog', (tester) async {
      await tester.pumpWidgetBuilder(
        _pluginShell(
          size: const Size(560, 520),
          builder:
              (context) => Center(
                child: FilledButton(
                  onPressed: () {
                    const StickyNotePlugin().showEditor(
                      context,
                      _stickyPanel(),
                      (_) {},
                    );
                  },
                  child: const Text('Open editor'),
                ),
              ),
        ),
        surfaceSize: const Size(560, 520),
      );
      await tester.tap(find.text('Open editor'));
      await tester.pumpAndSettle();
      await screenMatchesGolden(tester, 'board_sticky_editor_dialog');
    });

    testGoldens('standard panel chrome exposes depth and settings', (
      tester,
    ) async {
      await tester.pumpWidgetBuilder(
        _pluginShell(
          size: const Size(560, 520),
          builder:
              (context) => PanelSettingsDialog(
                panel: _standardPanel(),
                plugin: const MarkdownNotePlugin(),
                onEditColor: () {},
                onEditPanel: () {},
                onBringToFront: () {},
                onSendToBack: () {},
              ),
        ),
        surfaceSize: const Size(560, 520),
      );
      await tester.pump();

      expect(find.text('Panel settings'), findsOneWidget);
      expect(find.text('zIndex 7'), findsOneWidget);
      expect(find.text('Arrange'), findsOneWidget);
      await expectLater(
        find.byType(PanelSettingsDialog),
        matchesGoldenFile('goldens/board_standard_panel_settings.png'),
      );
    });
  });
}
