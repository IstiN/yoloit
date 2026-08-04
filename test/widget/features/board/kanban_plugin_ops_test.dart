import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/kanban_plugin.dart';

void main() {
  const plugin = KanbanPlugin();

  Future<void> pumpKanban(
    WidgetTester tester, {
    required Map<String, dynamic> Function() state,
    required ValueChanged<Map<String, dynamic>> onState,
    ThemeData? theme,
    bool readOnly = false,
  }) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return plugin.buildContent(
                  context,
                  BoardPanelInstance(
                    id: 'kanban',
                    type: KanbanPlugin.kTypeId,
                    title: 'Kanban',
                    bounds: const BoardPanelBounds(
                      x: 0,
                      y: 0,
                      width: 640,
                      height: 420,
                    ),
                    state: state(),
                  ),
                  BoardPanelRenderContext(
                    isSelected: true,
                    onFocus: () {},
                    onDelete: () {},
                    onUpdateState: (nextState) {
                      onState(nextState);
                      refresh(() {});
                    },
                    onShowEditor: () {},
                    readOnly: readOnly,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> cardsOf(Map<String, dynamic> state) =>
      (state['cards'] as List<dynamic>)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

  testWidgets('adds a column and clamps card columnIndex', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Todo', 'Done'],
      'cards': <Map<String, dynamic>>[
        {'id': 'c1', 'title': 'A', 'description': '', 'columnIndex': 7},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Add column'));
    await tester.pumpAndSettle();

    expect(state['columns'], ['Todo', 'Done', 'New Column']);
    expect(cardsOf(state).single['columnIndex'], 2);
  });

  testWidgets('deletes a column and remaps remaining cards', (tester) async {
    var state = <String, dynamic>{
      'columns': ['One', 'Two', 'Three'],
      'cards': <Map<String, dynamic>>[
        {'id': 'c0', 'title': 'In one', 'description': '', 'columnIndex': 0},
        {'id': 'c1', 'title': 'In two', 'description': '', 'columnIndex': 1},
        {'id': 'c2', 'title': 'In three', 'description': '', 'columnIndex': 2},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Edit columns').first);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete column').at(1));
    await tester.pumpAndSettle();

    expect(state['columns'], ['One', 'Three']);
    final cards = cardsOf(state);
    expect(cards.map((c) => c['id']), ['c0', 'c2']);
    expect(cards.map((c) => c['columnIndex']), [0, 1]);
  });

  testWidgets('moves a column right remapping cards and colors', (
    tester,
  ) async {
    var state = <String, dynamic>{
      'columns': ['A', 'B', 'C'],
      'columnColors': {'0': 'ff112233', '2': 'ff445566'},
      'cards': <Map<String, dynamic>>[
        {'id': 'ca', 'title': 'Card A', 'description': '', 'columnIndex': 0},
        {'id': 'cb', 'title': 'Card B', 'description': '', 'columnIndex': 1},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Edit columns').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move right').first);
    await tester.pumpAndSettle();

    expect(state['columns'], ['B', 'A', 'C']);
    final cards = cardsOf(state);
    expect(
      cards.firstWhere((c) => c['id'] == 'ca')['columnIndex'],
      1,
    );
    expect(
      cards.firstWhere((c) => c['id'] == 'cb')['columnIndex'],
      0,
    );
    expect(state['columnColors'], {'1': 'ff112233', '2': 'ff445566'});
  });

  testWidgets('moves a column left via header button', (tester) async {
    var state = <String, dynamic>{
      'columns': ['A', 'B'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Edit columns').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Move left').first);
    await tester.pumpAndSettle();

    expect(state['columns'], ['B', 'A']);
  });

  testWidgets('renames a column via double tap with fallback for empty name', (
    tester,
  ) async {
    var state = <String, dynamic>{
      'columns': ['Alpha', 'Beta'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.text('Alpha'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Alpha'));
    await tester.pumpAndSettle();

    final renameField = find.byType(TextField);
    expect(renameField, findsOneWidget);
    await tester.enterText(renameField, 'Gamma');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state['columns'], ['Gamma', 'Beta']);
    expect(find.byType(TextField), findsNothing);

    // Empty name falls back to the positional default.
    await tester.tap(find.text('Beta'));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.text('Beta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(state['columns'], ['Gamma', 'Column 2']);
  });

  testWidgets('sets a column color from the edit-mode picker', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Solo'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Edit columns').first);
    await tester.pumpAndSettle();

    final swatch = find.byWidgetPredicate(
      (widget) =>
          widget is Container &&
          widget.decoration is BoxDecoration &&
          (widget.decoration! as BoxDecoration).shape == BoxShape.circle,
    );
    expect(swatch, findsWidgets);
    await tester.tap(swatch.first);
    await tester.pumpAndSettle();

    final colors = Map<String, String>.from(
      state['columnColors'] as Map<dynamic, dynamic>,
    );
    final hex = colors['0'];
    expect(hex, isNotNull);
    expect(hex!.length, 8);
    expect(int.tryParse(hex, radix: 16), isNotNull);
  });

  testWidgets('adds cards through the inline field and ignores empty titles', (
    tester,
  ) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    // Confirm button path.
    await tester.tap(find.byTooltip('Add card').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Hello card');
    await tester.tap(find.byIcon(Icons.check));
    await tester.pumpAndSettle();

    var cards = cardsOf(state);
    expect(cards, hasLength(1));
    expect(cards.single['title'], 'Hello card');
    expect(cards.single['columnIndex'], 0);
    expect(find.byType(TextField), findsNothing);

    // Submit path with an empty title closes the field without saving.
    await tester.tap(find.byTooltip('Add card').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '   ');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    cards = cardsOf(state);
    expect(cards, hasLength(1));
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('deletes a card via its close button', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {'id': 'c1', 'title': 'Doomed', 'description': 'note', 'columnIndex': 0},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    expect(find.text('Doomed'), findsOneWidget);
    expect(find.text('note'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(cardsOf(state), isEmpty);
    expect(find.text('Doomed'), findsNothing);
  });

  testWidgets('filters cards through search with debounce, clear and close', (
    tester,
  ) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'c1',
          'title': 'Alpha task',
          'description': '',
          'columnIndex': 0,
        },
        {
          'id': 'c2',
          'title': 'Beta task',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.tap(find.byTooltip('Search cards'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'alpha');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();

    expect(find.text('Alpha task'), findsOneWidget);
    expect(find.text('Beta task'), findsNothing);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha task'), findsOneWidget);
    expect(find.text('Beta task'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'beta');
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('Alpha task'), findsNothing);
    expect(find.text('Beta task'), findsOneWidget);

    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.text('Alpha task'), findsOneWidget);
    expect(find.text('Beta task'), findsOneWidget);
    expect(find.byTooltip('Search cards'), findsOneWidget);
  });

  testWidgets('renders cards with all supported color string formats', (
    tester,
  ) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'c1',
          'title': 'Hash color',
          'description': '',
          'columnIndex': 0,
          'color': '#FF0000',
        },
        {
          'id': 'c2',
          'title': 'Hex prefix color',
          'description': '',
          'columnIndex': 0,
          'color': '0xFF00FF00',
        },
        {
          'id': 'c3',
          'title': 'Six digit color',
          'description': '',
          'columnIndex': 0,
          'color': '0000FF',
        },
        {
          'id': 'c4',
          'title': 'Invalid color',
          'description': '',
          'columnIndex': 0,
          'color': 'not-a-color',
        },
        {
          'id': 'c5',
          'title': 'Empty color',
          'description': '',
          'columnIndex': 0,
          'color': '',
        },
        {
          'id': 'c6',
          'title': 'No color',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    for (final title in [
      'Hash color',
      'Hex prefix color',
      'Six digit color',
      'Invalid color',
      'Empty color',
      'No color',
    ]) {
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('darkens bright header colors in a light theme', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Bright', 'Medium', 'Default'],
      'columnColors': {'0': 'ffffff00', '1': 'ffb3b3b3'},
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
      theme: AppThemePreset.islandsLight.theme,
    );

    final theme = AppThemePreset.islandsLight.theme;
    final primary = theme.extension<AppColorScheme>()!.primary;

    // Each column shows a zero count badge; colors follow luminance rules.
    final badges = find.text('0');
    expect(badges, findsNWidgets(3));
    final brightBadge = tester.widget<Text>(badges.at(0));
    final mediumBadge = tester.widget<Text>(badges.at(1));
    final defaultBadge = tester.widget<Text>(badges.at(2));

    expect(brightBadge.style!.color, isNot(const Color(0xffffff00)));
    expect(mediumBadge.style!.color, isNot(const Color(0xffb3b3b3)));
    expect(defaultBadge.style!.color, primary);
    expect(brightBadge.style!.color, isNot(mediumBadge.style!.color));

    // An invalid stored hex falls back to the theme primary.
    state = <String, dynamic>{
      'columns': ['Broken'],
      'columnColors': {'0': 'zzzz'},
      'cards': <Map<String, dynamic>>[],
    };
    await tester.pumpWidget(const SizedBox());
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
      theme: AppThemePreset.islandsLight.theme,
    );
    final fallbackBadge = tester.widget<Text>(find.text('0'));
    expect(fallbackBadge.style!.color, primary);
  });

  testWidgets('read-only mode blocks editing affordances', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {'id': 'c1', 'title': 'Locked', 'description': '', 'columnIndex': 0},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
      readOnly: true,
    );

    await tester.tap(find.byTooltip('Edit columns').first);
    await tester.pumpAndSettle();
    expect(find.text('Done'), findsNothing);

    await tester.tap(find.byTooltip('Add column'));
    await tester.pumpAndSettle();
    expect(state['columns'], ['Todo']);

    await tester.tap(find.byTooltip('Add card').first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(cardsOf(state), hasLength(1));
  });

  testWidgets('moves a card to another column by dragging', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Left', 'Right'],
      'cards': <Map<String, dynamic>>[
        {'id': 'c1', 'title': 'Drag me', 'description': '', 'columnIndex': 0},
      ],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );

    await tester.drag(find.text('Drag me'), const Offset(220, 0));
    await tester.pumpAndSettle();

    expect(cardsOf(state).single['columnIndex'], 1);
  });

  void mockClipboard(
    WidgetTester tester,
    Map<dynamic, dynamic>? Function(MethodCall call) handler,
  ) {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMessageHandler('flutter/platform', (message) async {
      final call = SystemChannels.platform.codec.decodeMethodCall(message);
      final result = handler(call);
      return SystemChannels.platform.codec.encodeSuccessEnvelope(result);
    });
    addTearDown(
      () => messenger.setMockMessageHandler('flutter/platform', null),
    );
  }

  testWidgets('ctrl+v with empty clipboard shows a snackbar', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );
    mockClipboard(tester, (call) => null);

    // Tap the board background to focus the keyboard listener.
    await tester.tapAt(const Offset(450, 400));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.text('Clipboard is empty'), findsOneWidget);
    expect(cardsOf(state), isEmpty);
  });

  testWidgets('ctrl+v pastes clipboard text as a new card', (tester) async {
    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[],
    };
    await pumpKanban(
      tester,
      state: () => state,
      onState: (next) => state = next,
    );
    mockClipboard(
      tester,
      (call) => {'text': 'Pasted title\nline one\nline two'},
    );

    await tester.tapAt(const Offset(450, 400));
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    final cards = cardsOf(state);
    expect(cards, hasLength(1));
    expect(cards.single['title'], 'Pasted title');
    expect(cards.single['description'], 'line one\nline two');
    expect(cards.single['columnIndex'], 0);
  });
}
