import 'dart:convert';
import 'dart:ui' show Brightness;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/core/theme/theme_manager.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import '../../../../helpers/fake_board_cubit.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('YoloitWebToolExecutor', () {
    late FakeBoardCubit cubit;
    late YoloitWebToolExecutor executor;

    setUp(() {
      cubit = FakeBoardCubit();
      executor = YoloitWebToolExecutor();
    });

    test('list_tools returns compact catalog', () async {
      final result = await executor.invoke(
        'list_tools',
        {},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded.containsKey('tools'), isTrue);
      expect(decoded['tools'], isA<List<dynamic>>());
    });

    test('unknown function returns error', () async {
      final result = await executor.invoke(
        'unknown_tool',
        {},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Unknown YoLoIT tool'));
    });

    test('missing boardCubit returns error', () async {
      final result = await executor.invoke('note:create', {
        'title': 'Note',
        'text': 'Hello',
      });
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('No board context'));
    });

    test('note:create creates markdown note', () async {
      final result = await executor.invoke(
        'yoloit_note_create',
        {'title': 'Note', 'text': 'Hello'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['command'], 'note:create');
      expect(cubit.createdNotes.length, 1);
      expect(cubit.createdNotes.first['title'], 'Note');
      expect(cubit.createdNotes.first['markdown'], 'Hello');
    });

    test('panel:create creates generic panel', () async {
      final result = await executor.invoke(
        'yoloit_panel_create',
        {'type': 'board.checklist', 'title': 'My Checklist'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['type'], 'board.checklist');
      expect(cubit.createdGenericPanels.length, 1);
      expect(cubit.createdGenericPanels.first.type, 'board.checklist');
      expect(cubit.createdGenericPanels.first.title, 'My Checklist');
    });

    test('panel:create returns error when type missing', () async {
      final result = await executor.invoke(
        'yoloit_panel_create',
        {'title': 'No type'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Missing panel type'));
    });

    test('panel:focus focuses panel by title', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'Target',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        ),
      );

      final result = await executor.invoke(
        'yoloit_panel_focus',
        {'panel': 'Target'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(cubit.focusedPanelIds, contains('p-1'));
    });

    test('panel:focus returns error when panel not found', () async {
      final result = await executor.invoke(
        'yoloit_panel_focus',
        {'panel': 'Missing'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Panel not found'));
    });

    test('board:focus switches active board', () async {
      cubit.addFakeBoard(
        const BoardDocument(id: 'b-2', name: 'Other'),
      );

      final result = await executor.invoke(
        'yoloit_board_focus',
        {'board': 'Other'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(cubit.activeBoardId, 'b-2');
    });

    test('sticky:create creates sticky panel', () async {
      final result = await executor.invoke(
        'yoloit_sticky_create',
        {'title': 'Sticky', 'text': 'Buy milk'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(cubit.createdGenericPanels.length, 1);
      expect(cubit.createdGenericPanels.first.type, 'board.note.sticky');
      expect(
        cubit.createdGenericPanels.first.state['text'],
        'Buy milk',
      );
    });

    test('shape:create creates shape panel', () async {
      final result = await executor.invoke(
        'yoloit_shape_create',
        {
          'shape': 'diamond',
          'title': 'Decision',
          'text': 'Go',
          'fill': '#FF0000',
          'stroke': '#00FF00',
        },
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final panel = cubit.createdGenericPanels.first;
      expect(panel.type, 'board.shape');
      expect(panel.state['shape'], 'diamond');
      expect(panel.state['text'], 'Go');
      expect(panel.state['fillColor'], '#ff0000');
      expect(panel.state['strokeColor'], '#00ff00');
    });

    test('frame:create creates frame panel', () async {
      final result = await executor.invoke(
        'yoloit_frame_create',
        {'title': 'Frame'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final panel = cubit.createdGenericPanels.first;
      expect(panel.type, 'board.shape');
      expect(panel.state['shape'], 'frame');
    });

    test('kanban:add-card adds card to existing kanban', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'k-1',
          type: 'board.kanban',
          title: 'Kanban',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'columns': ['Todo', 'Done'],
            'cards': <Map<String, dynamic>>[],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_kanban_add_card',
        {'panel': 'Kanban', 'column': 'Todo', 'title': 'Task 1'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['k-1'];
      expect(updated, isNotNull);
      final cards = updated!.state['cards'] as List;
      expect(cards.length, 1);
      expect((cards.first as Map<String, dynamic>)['title'], 'Task 1');
      expect((cards.first as Map<String, dynamic>)['columnIndex'], 0);
    });

    test('kanban:add-card falls back to first column', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'k-1',
          type: 'board.kanban',
          title: 'Kanban',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'columns': ['Backlog'],
            'cards': <Map<String, dynamic>>[],
          },
        ),
      );

      await executor.invoke(
        'yoloit_kanban_add_card',
        {'panel': 'Kanban', 'column': 'Unknown', 'title': 'Task'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );

      final updated = cubit.updatedPanels['k-1'];
      final cards = updated!.state['cards'] as List;
      expect((cards.first as Map<String, dynamic>)['columnIndex'], 0);
    });

    test('kanban:add-card returns error when panel missing', () async {
      final result = await executor.invoke(
        'yoloit_kanban_add_card',
        {'panel': 'Kanban', 'column': 'Todo', 'title': 'Task'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Kanban panel not found'));
    });

    test('checklist:add adds item to existing checklist', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Checklist',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'items': <Map<String, dynamic>>[]},
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_add',
        {'panel': 'Checklist', 'item': 'Milk'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['c-1'];
      final items = updated!.state['items'] as List;
      expect(items.length, 1);
      expect((items.first as Map<String, dynamic>)['text'], 'Milk');
      expect((items.first as Map<String, dynamic>)['checked'], isFalse);
    });

    test('checklist:add returns error when text missing', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Checklist',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'items': <Map<String, dynamic>>[]},
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_add',
        {'panel': 'Checklist'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Missing checklist item'));
    });

    test('link:create links two panels', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'A',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
        ),
      );
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-2',
          type: 'board.note.markdown',
          title: 'B',
          bounds: BoardPanelBounds(x: 20, y: 20, width: 10, height: 10),
        ),
      );

      final result = await executor.invoke(
        'yoloit_link_create',
        {'from': 'A', 'to': 'B'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(cubit.upsertedLinks.length, 1);
      expect(cubit.upsertedLinks.first.fromPanelId, 'p-1');
      expect(cubit.upsertedLinks.first.toPanelId, 'p-2');
    });

    test('link:create returns error when source missing', () async {
      final result = await executor.invoke(
        'yoloit_link_create',
        {'from': 'A', 'to': 'B'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('Source or target panel not found'));
    });

    test('panel returns panel details and state', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'Notes',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'markdown': '# Hello'},
        ),
      );

      final result = await executor.invoke(
        'yoloit_panel',
        {'panel': 'Notes'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['id'], 'p-1');
      expect(decoded['title'], 'Notes');
      expect((decoded['state'] as Map<String, dynamic>)['markdown'], '# Hello');
    });

    test('panel:help returns panel details with empty actions', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'Notes',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'markdown': '# Hello'},
        ),
      );

      final result = await executor.invoke(
        'yoloit_panel_help',
        {'panel': 'Notes'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect(decoded['actions'], isEmpty);
    });

    test('panels lists panels on active board', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'A',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        ),
      );
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-2',
          type: 'board.checklist',
          title: 'B',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
        ),
      );

      final result = await executor.invoke(
        'yoloit_panels',
        {},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final panels = decoded['panels'] as List;
      expect(panels.length, 2);
      expect((panels.first as Map<String, dynamic>)['title'], 'A');
    });

    test('note:get returns markdown content', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'p-1',
          type: 'board.note.markdown',
          title: 'Notes',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'markdown': '# Plan'},
        ),
      );

      final result = await executor.invoke(
        'yoloit_note_get',
        {'panel': 'Notes'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      expect((decoded['state'] as Map<String, dynamic>)['markdown'], '# Plan');
    });

    test('checklist:items returns items', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Shopping',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'items': [
              {'id': 'i-1', 'text': 'Milk', 'checked': false},
            ],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_items',
        {'panel': 'Shopping'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final items = decoded['items'] as List;
      expect(items.length, 1);
      expect((items.first as Map<String, dynamic>)['text'], 'Milk');
    });

    test('checklist:add finds first checklist panel when panel omitted', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Shopping',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {'items': <Map<String, dynamic>>[]},
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_add',
        {'item': 'Eggs'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['c-1'];
      final items = updated!.state['items'] as List;
      expect(items.length, 1);
      expect((items.first as Map<String, dynamic>)['text'], 'Eggs');
    });

    test('checklist:check toggles item by text', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Shopping',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'items': [
              {'id': 'i-1', 'text': 'Milk', 'checked': false},
            ],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_check',
        {'panel': 'Shopping', 'item': 'Milk'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['c-1'];
      final items = updated!.state['items'] as List;
      expect((items.first as Map<String, dynamic>)['checked'], isTrue);
    });

    test('checklist:remove deletes item by index', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'c-1',
          type: 'board.checklist',
          title: 'Shopping',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'items': [
              {'id': 'i-1', 'text': 'Milk', 'checked': false},
              {'id': 'i-2', 'text': 'Eggs', 'checked': false},
            ],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_checklist_remove',
        {'panel': 'Shopping', 'item': '0'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['c-1'];
      final items = updated!.state['items'] as List;
      expect(items.length, 1);
      expect((items.first as Map<String, dynamic>)['text'], 'Eggs');
    });

    test('kanban:cards and kanban:columns return board state', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'k-1',
          type: 'board.kanban',
          title: 'Board',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'columns': ['Todo', 'Done'],
            'cards': [
              {
                'id': 'card-1',
                'title': 'Task',
                'columnIndex': 0,
              },
            ],
          },
        ),
      );

      final cardsResult = await executor.invoke(
        'yoloit_kanban_cards',
        {'panel': 'Board'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final cardsDecoded = jsonDecode(cardsResult) as Map<String, dynamic>;
      expect(cardsDecoded['ok'], isTrue);
      expect((cardsDecoded['cards'] as List).length, 1);

      final columnsResult = await executor.invoke(
        'yoloit_kanban_columns',
        {'panel': 'Board'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final columnsDecoded = jsonDecode(columnsResult) as Map<String, dynamic>;
      expect(columnsDecoded['ok'], isTrue);
      expect(columnsDecoded['columns'], ['Todo', 'Done']);
    });

    test('kanban:move-card updates column index', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'k-1',
          type: 'board.kanban',
          title: 'Board',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'columns': ['Todo', 'Done'],
            'cards': [
              {'id': 'card-1', 'title': 'Task', 'columnIndex': 0},
            ],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_kanban_move_card',
        {'panel': 'Board', 'card_id': 'card-1', 'to_column': 'Done'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['k-1'];
      final cards = updated!.state['cards'] as List;
      expect((cards.first as Map<String, dynamic>)['columnIndex'], 1);
    });

    test('kanban:remove-column deletes column and its cards', () async {
      cubit.addFakePanel(
        const BoardPanelInstance(
          id: 'k-1',
          type: 'board.kanban',
          title: 'Board',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          state: {
            'columns': ['Todo', 'Done'],
            'cards': [
              {'id': 'card-1', 'title': 'Task', 'columnIndex': 0},
              {'id': 'card-2', 'title': 'Other', 'columnIndex': 1},
            ],
          },
        ),
      );

      final result = await executor.invoke(
        'yoloit_kanban_remove_column',
        {'panel': 'Board', 'column': 'Todo'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isTrue);
      final updated = cubit.updatedPanels['k-1'];
      expect(updated!.state['columns'], ['Done']);
      final cards = updated.state['cards'] as List;
      expect(cards.length, 1);
      expect((cards.first as Map<String, dynamic>)['title'], 'Other');
    });

    test('unsupported command returns error', () async {
      final tool = YoloitCliToolCatalog.tools.firstWhere(
        (t) => t.command == 'terminal:output',
      );
      final result = await executor.invoke(
        tool.functionName,
        {'panel': 'Terminal'},
        runtimeContext: ChatRuntimeContext(boardCubit: cubit),
      );
      final decoded = jsonDecode(result) as Map<String, dynamic>;
      expect(decoded['ok'], isFalse);
      expect(decoded['error'], contains('not available in the browser'));
    });

    group('board operations', () {
      test('board:create creates a new board', () async {
        final result = await executor.invoke(
          'yoloit_board_create',
          {'name': 'New Board'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['id'], startsWith('board-'));
        expect(decoded['name'], 'New Board');
      });

      test('board:rename renames active board', () async {
        final result = await executor.invoke(
          'yoloit_board_rename',
          {'new_name': 'Renamed'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.state.activeBoard?.name, 'Renamed');
      });

      test('board:delete removes active board', () async {
        cubit.addFakeBoard(
          const BoardDocument(id: 'b-other', name: 'Other', panels: []),
        );
        final result = await executor.invoke(
          'yoloit_board_delete',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(
          cubit.state.boards.any((b) => b.id == 'b-1'),
          isFalse,
        );
      });

      test('board:archive and board:unarchive toggle archived flag', () async {
        final result = await executor.invoke(
          'yoloit_board_archive',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(result) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.state.activeBoard?.archived, isTrue);

        final result2 = await executor.invoke(
          'yoloit_board_unarchive',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(result2) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.state.activeBoard?.archived, isFalse);
      });

      test('board:zoom updates viewport scale', () async {
        final result = await executor.invoke(
          'yoloit_board_zoom',
          {'scale': 1.5},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.state.activeBoard?.viewport.scale, closeTo(1.5, 0.01));
      });

      test('board:translate updates viewport translation', () async {
        final result = await executor.invoke(
          'yoloit_board_translate',
          {'x': 100.0, 'y': 200.0},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.state.activeBoard?.viewport.translation.dx, closeTo(100, 0.01));
        expect(cubit.state.activeBoard?.viewport.translation.dy, closeTo(200, 0.01));
      });

      test('board:snapshot returns panels', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-snap',
            type: 'board.note.markdown',
            title: 'Snap',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
          ),
        );
        final result = await executor.invoke(
          'yoloit_board_snapshot',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['panels'] as List).length, 1);
      });

      test('board:diagram returns mermaid', () async {
        final result = await executor.invoke(
          'yoloit_board_diagram',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['diagram'], contains('graph LR'));
      });

      test('board:apply creates panels from YAML', () async {
        const yaml = '''
- action: panel.create
  type: board.note.markdown
  title: Applied Note
  state:
    markdown: Hello
''';
        final result = await executor.invoke(
          'yoloit_board_apply',
          {'yaml': yaml},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(
          cubit.state.activeBoard?.panels.any((p) => p.title == 'Applied Note'),
          isTrue,
        );
      });
    });

    group('drawings', () {
      test('draw:list returns empty list by default', () async {
        final result = await executor.invoke(
          'yoloit_draw_list',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['drawings'], isEmpty);
      });

      test('draw:add creates a line drawing', () async {
        final result = await executor.invoke(
          'yoloit_draw_add',
          {
            'type': 'line',
            'x1': 0.0,
            'y1': 0.0,
            'x2': 100.0,
            'y2': 100.0,
            'color': '#FF0000',
            'width': 2.0,
          },
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.addedDrawings.length, 1);
      });

      test('draw:remove deletes a drawing', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-dummy',
            type: 'board.note.markdown',
            title: 'D',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        );
        final addResult = await executor.invoke(
          'yoloit_draw_add',
          {
            'type': 'line',
            'x1': 0.0,
            'y1': 0.0,
            'x2': 100.0,
            'y2': 100.0,
          },
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final id = (jsonDecode(addResult) as Map<String, dynamic>)['id'] as String;
        final result = await executor.invoke(
          'yoloit_draw_remove',
          {'id': id},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.removedDrawingIds, contains(id));
      });
    });

    group('links advanced', () {
      test('links lists existing links', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-a',
            type: 'board.note.markdown',
            title: 'A',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        );
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-b',
            type: 'board.note.markdown',
            title: 'B',
            bounds: BoardPanelBounds(x: 20, y: 20, width: 10, height: 10),
          ),
        );
        await executor.invoke(
          'yoloit_link_create',
          {'from': 'A', 'to': 'B'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final result = await executor.invoke(
          'yoloit_links',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['links'] as List).length, 1);
      });

      test('link:delete removes a link', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-a',
            type: 'board.note.markdown',
            title: 'A',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        );
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-b',
            type: 'board.note.markdown',
            title: 'B',
            bounds: BoardPanelBounds(x: 20, y: 20, width: 10, height: 10),
          ),
        );
        final createResult = await executor.invoke(
          'yoloit_link_create',
          {'from': 'A', 'to': 'B'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final linkId = (jsonDecode(createResult) as Map<String, dynamic>)['id'] as String;
        final result = await executor.invoke(
          'yoloit_link_delete',
          {'link_id': linkId},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.removedLinkIds, contains(linkId));
      });
    });

    group('groups', () {
      test('group:create creates a group', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-g1',
            type: 'board.note.markdown',
            title: 'G1',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 10, height: 10),
          ),
        );
        final result = await executor.invoke(
          'yoloit_group_create',
          {'name': 'My Group', 'panels': 'p-g1'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.createdGroups.length, 1);
        expect(cubit.createdGroups.first.name, 'My Group');
      });

      test('groups lists groups', () async {
        await executor.invoke(
          'yoloit_group_create',
          {'name': 'Listed'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final result = await executor.invoke(
          'yoloit_groups',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['groups'] as List).length, 1);
      });

      test('group:rename renames a group', () async {
        await executor.invoke(
          'yoloit_group_create',
          {'name': 'Old'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final result = await executor.invoke(
          'yoloit_group_rename',
          {'group': 'Old', 'name': 'New'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(
          cubit.state.activeBoard?.groups.first.name,
          'New',
        );
      });

      test('group:collapse and group:expand toggle collapsed', () async {
        await executor.invoke(
          'yoloit_group_create',
          {'name': 'Toggle'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final result1 = await executor.invoke(
          'yoloit_group_collapse',
          {'group': 'Toggle'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(result1) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.collapsed, isTrue);

        final result2 = await executor.invoke(
          'yoloit_group_expand',
          {'group': 'Toggle'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(result2) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.state.activeBoard?.groups.first.collapsed, isFalse);
      });
    });

    group('webpage', () {
      test('panel:create board.webpage creates webpage panel', () async {
        final result = await executor.invoke(
          'yoloit_panel_create',
          {'type': 'board.webpage', 'title': 'Web'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.createdGenericPanels.last.type, 'board.webpage');
      });

      test('web:open normalizes and sets URL', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-web',
            type: 'board.webpage',
            title: 'Web',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {'url': ''},
          ),
        );
        final result = await executor.invoke(
          'yoloit_web_open',
          {'panel': 'Web', 'url': 'example.com'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.updatedPanels['p-web']?.state['url'], 'https://example.com');
      });

      test('web:exec returns unsupported error', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-web',
            type: 'board.webpage',
            title: 'Web',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {'url': 'https://example.com'},
          ),
        );
        final result = await executor.invoke(
          'yoloit_web_exec',
          {'panel': 'Web', 'js': '1+1'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isFalse);
        expect(decoded['error'], contains('not available here'));
      });
    });

    group('ui panels', () {
      test('ui:create creates a UI panel with default tree', () async {
        final result = await executor.invoke(
          'yoloit_ui_create',
          {'title': 'UI'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.createdGenericPanels.last.type, 'board.ui');
      });

      test('ui:render updates tree', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-ui',
            type: 'board.ui',
            title: 'UI',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {'tree': <String, dynamic>{}, '_scripts': <String>[]},
          ),
        );
        final result = await executor.invoke(
          'yoloit_ui_render',
          {'panel': 'UI', 'tree': '{"type":"text","text":"Hi"}'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((cubit.updatedPanels['p-ui']!.state['tree'] as Map<String, dynamic>)['type'], 'text');
      });
    });

    group('table', () {
      test('table:create creates table panel', () async {
        final result = await executor.invoke(
          'yoloit_table_create',
          {'title': 'T'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.createdGenericPanels.last.type, 'board.table');
      });

      test('table:set replaces columns and rows', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-tbl',
            type: 'board.table',
            title: 'Table',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_table_set',
          {
            'panel': 'Table',
            'columns': '[{"id":"c1","title":"Col1"}]',
            'rows': '[{"id":"r1","c1":"v1"}]',
          },
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        final state = cubit.updatedPanels['p-tbl']!.state;
        expect((state['columns'] as List).length, 1);
        expect((state['rows'] as List).length, 1);
      });

      test('table:add-row and table:remove-row mutate rows', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-tbl',
            type: 'board.table',
            title: 'Table',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {
              'columns': [
                {'id': 'c1', 'title': 'Col1'},
              ],
              'rows': [
                {'id': 'r-existing', 'c1': 'existing'},
              ],
            },
          ),
        );
        final addResult = await executor.invoke(
          'yoloit_table_add_row',
          {'panel': 'Table', 'cells': '{"c1":"v1"}'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final addDecoded = jsonDecode(addResult) as Map<String, dynamic>;
        expect(addDecoded['ok'], isTrue);
        final rowId = addDecoded['id'] as String;
        expect(
          (cubit.updatedPanels['p-tbl']!.state['rows'] as List).length,
          2,
        );

        final removeResult = await executor.invoke(
          'yoloit_table_remove_row',
          {'panel': 'Table', 'row_id': rowId},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final removeDecoded = jsonDecode(removeResult) as Map<String, dynamic>;
        expect(removeDecoded['ok'], isTrue);
        expect(
          (cubit.updatedPanels['p-tbl']!.state['rows'] as List).length,
          1,
        );
      });
    });

    group('chart', () {
      test('chart:create creates chart panel', () async {
        final result = await executor.invoke(
          'yoloit_chart_create',
          {'title': 'Chart', 'type': 'bar'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        final panel = cubit.createdGenericPanels.last;
        expect(panel.type, 'board.chart');
        expect(panel.state['type'], 'bar');
      });

      test('chart:set-data and chart:set-type update state', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-ch',
            type: 'board.chart',
            title: 'Chart',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_chart_set_data',
          {
            'panel': 'Chart',
            'data': '[{"x":"A","y":1}]',
            'xKey': 'x',
            'yKey': 'y',
          },
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);

        final typeResult = await executor.invoke(
          'yoloit_chart_set_type',
          {'panel': 'Chart', 'type': 'pie'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final typeDecoded = jsonDecode(typeResult) as Map<String, dynamic>;
        expect(typeDecoded['ok'], isTrue);
        expect(cubit.updatedPanels['p-ch']?.state['type'], 'pie');
        expect((cubit.updatedPanels['p-ch']?.state['data'] as List).length, 1);
      });

      test('chart:link-table links to table panel', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-tbl2',
            type: 'board.table',
            title: 'Source Table',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-ch2',
            type: 'board.chart',
            title: 'Chart',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_chart_link_table',
          {'panel': 'Chart', 'table_panel': 'Source Table'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.updatedPanels['p-ch2']?.state['tablePanelId'], 'p-tbl2');
      });
    });

    group('timer', () {
      test('timer:create creates a timer panel', () async {
        final result = await executor.invoke(
          'yoloit_timer_create',
          {'duration': '5m', 'label': 'Pomodoro'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        final panel = cubit.createdGenericPanels.last;
        expect(panel.type, 'board.timer');
        expect(panel.state['duration'], 300);
        expect(panel.state['label'], 'Pomodoro');
      });

      test('timer:start and timer:reset mutate state', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-tmr',
            type: 'board.timer',
            title: 'Timer',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {
              'duration': 60,
              'remaining': 60,
              'isRunning': false,
              'isPaused': false,
              'completed': false,
            },
          ),
        );
        final startResult = await executor.invoke(
          'yoloit_timer_start',
          {'panel': 'Timer'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(startResult) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.updatedPanels['p-tmr']?.state['isRunning'], isTrue);

        final resetResult = await executor.invoke(
          'yoloit_timer_reset',
          {'panel': 'Timer'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(resetResult) as Map<String, dynamic>)['ok'], isTrue);
        expect(cubit.updatedPanels['p-tmr']?.state['isRunning'], isFalse);
        expect(cubit.updatedPanels['p-tmr']?.state['remaining'], 60);
      });
    });

    group('calendar', () {
      test('calendar:create creates calendar panel', () async {
        final result = await executor.invoke(
          'yoloit_calendar_create',
          {'title': 'Cal'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.createdGenericPanels.last.type, 'board.calendar');
      });

      test('calendar:set-view updates view', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-cal',
            type: 'board.calendar',
            title: 'Cal',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_calendar_set_view',
          {'panel': 'Cal', 'view': 'week'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(cubit.updatedPanels['p-cal']?.state['view'], 'week');
      });

      test('calendar:add-event and calendar:events round-trip', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-cal',
            type: 'board.calendar',
            title: 'Cal',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final start = DateTime(2026, 7, 7, 10, 0).toIso8601String();
        final addResult = await executor.invoke(
          'yoloit_calendar_add_event',
          {
            'panel': 'Cal',
            'title': 'Standup',
            'start': start,
          },
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final addDecoded = jsonDecode(addResult) as Map<String, dynamic>;
        expect(addDecoded['ok'], isTrue);
        final eventId = addDecoded['id'] as String;

        final eventsResult = await executor.invoke(
          'yoloit_calendar_events',
          {'panel': 'Cal'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final eventsDecoded = jsonDecode(eventsResult) as Map<String, dynamic>;
        expect(eventsDecoded['ok'], isTrue);
        expect((eventsDecoded['events'] as List).length, 1);
        expect(
          ((eventsDecoded['events'] as List).first as Map<String, dynamic>)['title'],
          'Standup',
        );

        final deleteResult = await executor.invoke(
          'yoloit_calendar_delete_event',
          {'panel': 'Cal', 'event_id': eventId},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(deleteResult) as Map<String, dynamic>)['ok'], isTrue);

        final eventsResult2 = await executor.invoke(
          'yoloit_calendar_events',
          {'panel': 'Cal'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final eventsDecoded2 = jsonDecode(eventsResult2) as Map<String, dynamic>;
        expect((eventsDecoded2['events'] as List).length, 0);
      });
    });

    group('themes', () {
      late AppThemePreset originalPreset;
      late Brightness originalBrightness;

      setUp(() {
        SharedPreferences.setMockInitialValues({});
        originalPreset = ThemeManager.instance.current;
        originalBrightness = ThemeManager.instance.brightness;
      });

      tearDown(() async {
        await ThemeManager.instance.setTheme(originalPreset);
        await ThemeManager.instance.setBrightness(originalBrightness);
        await ThemeManager.instance.clearColorOverrides();
      });

      test('theme returns current theme info', () async {
        final result = await executor.invoke(
          'yoloit_theme',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['preset'], ThemeManager.instance.current.name);
      });

      test('theme:presets lists presets', () async {
        final result = await executor.invoke(
          'yoloit_theme_presets',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['presets'] as List).length, AppThemePreset.values.length);
      });

      test('theme:set switches preset', () async {
        final result = await executor.invoke(
          'yoloit_theme_set',
          {'name': 'cyberGreen'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(ThemeManager.instance.current, AppThemePreset.cyberGreen);
      });

      test('theme:brightness toggles brightness', () async {
        final result = await executor.invoke(
          'yoloit_theme_brightness',
          {'mode': 'dark'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(ThemeManager.instance.brightness, Brightness.dark);
      });

      test('theme:color and theme:reset-color manage overrides', () async {
        final slot = ThemeManager.colorCategories.values.first.first.key;
        final colorResult = await executor.invoke(
          'yoloit_theme_color',
          {'slot': slot, 'color': '#FF0000'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(colorResult) as Map<String, dynamic>)['ok'], isTrue);
        expect(ThemeManager.instance.hasOverrides, isTrue);

        final resetResult = await executor.invoke(
          'yoloit_theme_reset_color',
          {'slot': slot},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        expect((jsonDecode(resetResult) as Map<String, dynamic>)['ok'], isTrue);
      });

      test('theme:slots lists slots', () async {
        final result = await executor.invoke(
          'yoloit_theme_slots',
          {},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['slots'] as List).isNotEmpty, isTrue);
      });
    });

    group('help and search', () {
      test('help returns tools catalog', () async {
        final result = await executor.invoke(
          'yoloit_help',
          {'format': 'tools'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded.containsKey('tools'), isTrue);
      });

      test('search finds panel by title', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-search',
            type: 'board.note.markdown',
            title: 'UniqueAlpha',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_search',
          {'query': 'UniqueAlpha'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(
          (decoded['results'] as List).any(
            (r) => (r as Map<String, dynamic>)['title'] == 'UniqueAlpha',
          ),
          isTrue,
        );
      });
    });

    group('yolochat', () {
      test('yolochat:config returns panel config', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-chat',
            type: 'board.chat',
            title: 'AI Chat',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {
              'config': {
                'sessionName': 'Chat',
                'provider': 'openrouter',
                'model': 'mistral',
              },
            },
          ),
        );
        final result = await executor.invoke(
          'yoloit_yolochat_config',
          {'panel': 'AI Chat'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect((decoded['config'] as Map<String, dynamic>)['provider'], 'openrouter');
      });

      test('yolochat:status returns not processing for new panel', () async {
        cubit.addFakePanel(
          const BoardPanelInstance(
            id: 'p-chat',
            type: 'board.chat',
            title: 'AI Chat',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
            state: {},
          ),
        );
        final result = await executor.invoke(
          'yoloit_yolochat_status',
          {'panel': 'AI Chat'},
          runtimeContext: ChatRuntimeContext(boardCubit: cubit),
        );
        final decoded = jsonDecode(result) as Map<String, dynamic>;
        expect(decoded['ok'], isTrue);
        expect(decoded['isProcessing'], isFalse);
      });
    });
  });
}
