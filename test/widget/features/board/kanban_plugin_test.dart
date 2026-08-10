import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_panel_plugin.dart';
import 'package:yoloit/features/board/events/board_event_bus.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/kanban_plugin.dart';

/// Pumps the kanban content for [initialState] (optionally inside a
/// [BlocProvider] with [cubit]) and returns a reader for the current state.
Future<Map<String, dynamic> Function()> pumpKanban(
  WidgetTester tester, {
  required Map<String, dynamic> initialState,
  BoardCubit? cubit,
}) async {
  tester.view.physicalSize = const Size(900, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  var state = initialState;

  BoardPanelInstance panelForState() => BoardPanelInstance(
    id: 'kanban',
    type: KanbanPlugin.kTypeId,
    title: 'Kanban',
    bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 420),
    state: state,
  );

  late StateSetter refresh;
  Widget content = StatefulBuilder(
    builder: (context, setState) {
      refresh = setState;
      return const KanbanPlugin().buildContent(
        context,
        panelForState(),
        BoardPanelRenderContext(
          isSelected: true,
          onFocus: () {},
          onDelete: () {},
          onUpdateState: (nextState) {
            state = nextState;
            refresh(() {});
          },
          onShowEditor: () {},
        ),
      );
    },
  );
  if (cubit != null) {
    content = BlocProvider.value(value: cubit, child: content);
  }

  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(width: 640, height: 420, child: content),
      ),
    ),
  );
  return () => state;
}

BoardCubit cubitWithBoard(List<BoardPanelInstance> panels) {
  final cubit = BoardCubit();
  addTearDown(cubit.close);
  cubit.emit(
    BoardState(
      boards: [BoardDocument(id: 'board', name: 'Board', panels: panels)],
      activeBoardId: 'board',
      isLoaded: true,
    ),
  );
  return cubit;
}

BoardPanelInstance chatPanel(String id, String title) => BoardPanelInstance(
  id: id,
  type: ChatPanelPlugin.kTypeId,
  title: title,
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 320, height: 300),
);

List<Map<String, dynamic>> cardsOf(Map<String, dynamic> state) =>
    (state['cards'] as List<dynamic>)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();

void main() {
  const plugin = KanbanPlugin();

  testWidgets('kanban card opens editor and saves card fields', (tester) async {
    tester.view.physicalSize = const Size(900, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var state = <String, dynamic>{
      'columns': ['Todo', 'Done'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'card-1',
          'title': 'Old title',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };

    BoardPanelInstance panelForState() => BoardPanelInstance(
      id: 'kanban',
      type: KanbanPlugin.kTypeId,
      title: 'Kanban',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 420),
      state: state,
    );

    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return plugin.buildContent(
                  context,
                  panelForState(),
                  BoardPanelRenderContext(
                    isSelected: true,
                    onFocus: () {},
                    onDelete: () {},
                    onUpdateState: (nextState) {
                      state = nextState;
                      refresh(() {});
                    },
                    onShowEditor: () {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();

    expect(find.text('Edit kanban card'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'New title');
    await tester.enterText(fields.at(1), 'Long card description');
    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final cards = state['cards'] as List<dynamic>;
    final card = Map<String, dynamic>.from(cards.single as Map);
    expect(card['title'], 'New title');
    expect(card['description'], 'Long card description');
    expect(card['columnIndex'], 1);
  });

  testWidgets('kanban card editor preview renders markdown description', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var state = <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'card-1',
          'title': 'Card',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };

    BoardPanelInstance panelForState() => BoardPanelInstance(
      id: 'kanban',
      type: KanbanPlugin.kTypeId,
      title: 'Kanban',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 640, height: 420),
      state: state,
    );

    late StateSetter refresh;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: SizedBox(
            width: 640,
            height: 420,
            child: StatefulBuilder(
              builder: (context, setState) {
                refresh = setState;
                return plugin.buildContent(
                  context,
                  panelForState(),
                  BoardPanelRenderContext(
                    isSelected: true,
                    onFocus: () {},
                    onDelete: () {},
                    onUpdateState: (nextState) {
                      state = nextState;
                      refresh(() {});
                    },
                    onShowEditor: () {},
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Card'));
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(1), '**Preview me**');
    await tester.tap(find.text('Preview'));
    await tester.pumpAndSettle();

    expect(fields, findsOneWidget);
    expect(find.text('**Preview me**'), findsNothing);
    expect(find.textContaining('Preview me'), findsWidgets);
  });

  group('send card to chat', () {
    List<KanbanCardToChatEvent> captureChatEvents() {
      final events = <KanbanCardToChatEvent>[];
      final sub = BoardEventBus.instance
          .on<KanbanCardToChatEvent>()
          .listen(events.add);
      addTearDown(sub.cancel);
      return events;
    }

    Map<String, dynamic> singleCardState() => <String, dynamic>{
      'columns': ['Todo'],
      'cards': <Map<String, dynamic>>[
        {
          'id': 'c1',
          'title': 'Fix bug',
          'description': 'Steps here',
          'columnIndex': 0,
        },
      ],
    };

    testWidgets('emits card text to the only chat panel', (tester) async {
      final cubit = cubitWithBoard([chatPanel('chat-1', 'Chat')]);
      final events = captureChatEvents();
      await pumpKanban(tester, cubit: cubit, initialState: singleCardState());

      await tester.tap(find.byTooltip('Send to chat'));
      await tester.pump();

      expect(events, hasLength(1));
      expect(events.single.targetPanelId, 'chat-1');
      expect(events.single.text, 'Fix bug\n\nSteps here');
    });

    testWidgets('shows a snackbar when the board has no chat panels', (
      tester,
    ) async {
      final cubit = cubitWithBoard(const []);
      final events = captureChatEvents();
      await pumpKanban(tester, cubit: cubit, initialState: singleCardState());

      await tester.tap(find.byTooltip('Send to chat'));
      await tester.pump();

      expect(find.text('No chat panels on this board'), findsOneWidget);
      expect(events, isEmpty);
    });

    testWidgets('lets the user pick a chat panel when several exist', (
      tester,
    ) async {
      final cubit = cubitWithBoard([
        chatPanel('chat-a', 'Alpha Chat'),
        chatPanel('chat-b', 'Beta Chat'),
      ]);
      final events = captureChatEvents();
      await pumpKanban(tester, cubit: cubit, initialState: singleCardState());

      await tester.tap(find.byTooltip('Send to chat'));
      await tester.pumpAndSettle();

      expect(find.text('Alpha Chat'), findsOneWidget);
      await tester.tap(find.text('Beta Chat'));
      await tester.pumpAndSettle();

      expect(events, hasLength(1));
      expect(events.single.targetPanelId, 'chat-b');
      expect(events.single.text, 'Fix bug\n\nSteps here');
    });
  });

  group('card color parsing in the editor', () {
    Map<String, dynamic> coloredCardsState() => <String, dynamic>{
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
          'title': 'Plain color',
          'description': '',
          'columnIndex': 0,
          'color': '0000FF',
        },
        {
          'id': 'c4',
          'title': 'Broken color',
          'description': '',
          'columnIndex': 0,
          'color': 'not-a-color',
        },
        {
          'id': 'c5',
          'title': 'No color',
          'description': '',
          'columnIndex': 0,
        },
      ],
    };

    Future<void> saveCard(WidgetTester tester, String title) async {
      await tester.tap(find.text(title));
      await tester.pumpAndSettle();
      expect(find.text('Edit kanban card'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
    }

    testWidgets('stored colors round-trip through the editor', (tester) async {
      final readState = await pumpKanban(
        tester,
        initialState: coloredCardsState(),
      );

      await saveCard(tester, 'Hash color');
      await saveCard(tester, 'Hex prefix color');
      await saveCard(tester, 'Plain color');

      final cards = cardsOf(readState());
      expect(cards[0]['color'], '#FF0000');
      expect(cards[1]['color'], '#00FF00');
      expect(cards[2]['color'], '#0000FF');
    });

    testWidgets('missing or invalid colors are cleared on save', (
      tester,
    ) async {
      final readState = await pumpKanban(
        tester,
        initialState: coloredCardsState(),
      );

      await saveCard(tester, 'Broken color');
      await saveCard(tester, 'No color');

      final cards = cardsOf(readState());
      expect(cards[3]['color'], '');
      expect(cards[4]['color'], '');
    });
  });

  group('description smart paste', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    String descriptionText(WidgetTester tester) =>
        tester
            .widget<TextField>(find.byType(TextField).at(1))
            .controller!
            .text;

    // The smart-paste pipeline resolves clipboard text against the real
    // filesystem (ClipboardFileService.tryResolveTextAsFilePath), so the key
    // events must be dispatched inside runAsync where dart:io futures
    // actually complete; a fake-async zone would hang the paste forever.
    Future<void> sendPasteKeys(WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
        // Give the real async clipboard + file checks time to finish and the
        // insertion a chance to land in the controller.
        for (var i = 0; i < 20; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
          if (descriptionText(tester).isNotEmpty) return;
        }
      });
      await tester.pumpAndSettle();
    }

    void mockClipboardHandler(String? Function() text) {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.getData') {
          final value = text();
          if (value == null) return null;
          return <String, dynamic>{'text': value};
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
    }

    Future<Map<String, dynamic> Function()> openPasteEditor(
      WidgetTester tester,
    ) async {
      final readState = await pumpKanban(
        tester,
        initialState: <String, dynamic>{
          'columns': ['Todo'],
          'cards': <Map<String, dynamic>>[
            {
              'id': 'c1',
              'title': 'Paste target',
              'description': '',
              'columnIndex': 0,
            },
          ],
        },
      );
      await tester.tap(find.text('Paste target'));
      await tester.pumpAndSettle();
      expect(find.text('Edit kanban card'), findsOneWidget);
      return readState;
    }

    testWidgets('inserts clipboard text and ignores an empty clipboard', (
      tester,
    ) async {
      String? clipText;
      mockClipboardHandler(() => clipText);

      final readState = await openPasteEditor(tester);

      // Empty clipboard: nothing is inserted.
      await sendPasteKeys(tester);
      expect(descriptionText(tester), '');

      // Short safe text resolves inline and lands in the description.
      clipText = 'hello pasted world';
      await sendPasteKeys(tester);
      expect(descriptionText(tester), 'hello pasted world');

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(cardsOf(readState()).single['description'], 'hello pasted world');
    });

    testWidgets('pastes a clipboard URL inline', (tester) async {
      mockClipboardHandler(() => 'https://example.com/spec');

      await openPasteEditor(tester);
      await sendPasteKeys(tester);

      expect(descriptionText(tester), 'https://example.com/spec');
    });
  });
}
