import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/sticky_note_plugin.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('records panel changes as append-only history events', () async {
    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board')],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    const panel = BoardPanelInstance(
      id: 'panel-1',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky note',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 240, height: 180),
      state: {'text': 'long article draft'},
    );

    await cubit.addPanel(panel);
    await cubit.updatePanelColor('panel-1', color: Colors.pink);
    await cubit.removePanel('panel-1');

    final events = await cubit.historyForBoard('board');

    expect(events.map((event) => event.type), [
      'panel.created',
      'panel.updated',
      'panel.deleted',
    ]);
    expect(events.map((event) => event.revision), [1, 2, 3]);
    expect(events.last.before!['state'], {'text': 'long article draft'});
    expect(cubit.state.activeBoard!.metadata['historyRevision'], 3);
  });

  test('restores a deleted panel from its history event', () async {
    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board')],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    const panel = BoardPanelInstance(
      id: 'panel-1',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky note',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 240, height: 180),
      state: {'text': 'restore this article'},
    );

    await cubit.addPanel(panel);
    await cubit.removePanel('panel-1');
    final deletedEvent = (await cubit.historyForBoard(
      'board',
    )).lastWhere((event) => event.type == 'panel.deleted');

    final restored = await cubit.restorePanelFromEvent(
      'board',
      deletedEvent.opId,
    );

    expect(restored, isTrue);
    final restoredPanel = cubit.state.activeBoard!.panels.single;
    expect(restoredPanel.id, 'panel-1');
    expect(restoredPanel.state['text'], 'restore this article');
    expect(cubit.state.activeBoard!.viewport.focusedPanelId, 'panel-1');

    final events = await cubit.historyForBoard('board');
    expect(events.last.type, 'panel.restored');
    expect(events.last.restoresOpId, deletedEvent.opId);
  });

  test('restores an earlier state over an existing panel', () async {
    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board')],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    const panel = BoardPanelInstance(
      id: 'panel-1',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky note',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 240, height: 180),
      state: {'text': 'original draft'},
    );

    await cubit.addPanel(panel);
    await cubit.updatePanel(
      'panel-1',
      (panel) => panel.copyWith(state: {'text': 'bad rewrite'}),
    );
    final updateEvent = (await cubit.historyForBoard(
      'board',
    )).lastWhere((event) => event.type == 'panel.updated');

    final restored = await cubit.restorePanelFromEvent(
      'board',
      updateEvent.opId,
    );

    expect(restored, isTrue);
    expect(
      cubit.state.activeBoard!.panels.single.state['text'],
      'original draft',
    );
    final events = await cubit.historyForBoard('board');
    expect(events.last.type, 'panel.restored');
    expect(events.last.before!['state'], {'text': 'bad rewrite'});
  });

  test(
    'undoLatestPanelHistory walks backward without toggling restored state',
    () async {
      final historyStore = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
      addTearDown(cubit.close);
      cubit.emit(
        const BoardState(
          boards: [BoardDocument(id: 'board', name: 'Board')],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      const panel = BoardPanelInstance(
        id: 'panel-1',
        type: StickyNotePlugin.kTypeId,
        title: 'Sticky note',
        bounds: BoardPanelBounds(x: 10, y: 20, width: 240, height: 180),
        state: {'text': 'original draft'},
      );

      await cubit.addPanel(panel);
      await cubit.updatePanel(
        'panel-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 320, height: 260),
        ),
      );

      final firstUndo = await cubit.undoLatestPanelHistory('board');
      final restoredPanel = cubit.state.activeBoard!.panels.single;
      final secondUndo = await cubit.undoLatestPanelHistory('board');

      expect(firstUndo, isTrue);
      expect(restoredPanel.bounds.width, 240);
      expect(restoredPanel.bounds.height, 180);
      expect(secondUndo, isTrue);
      expect(cubit.state.activeBoard!.panels, isEmpty);
    },
  );

  test(
    'undoLatestPanelHistory restores resized shape after json snapshots',
    () async {
      final historyStore = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
      addTearDown(cubit.close);
      cubit.emit(
        const BoardState(
          boards: [BoardDocument(id: 'board', name: 'Board')],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      const panel = BoardPanelInstance(
        id: 'shape-1',
        type: 'board.shape',
        title: 'Rhombus',
        bounds: BoardPanelBounds(x: 10, y: 20, width: 120, height: 120),
        state: {'shape': 'diamond'},
      );

      await cubit.addPanel(panel);
      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(
          bounds: panel.bounds.copyWith(width: 260, height: 180),
        ),
      );

      final undone = await cubit.undoLatestPanelHistory('board');

      expect(undone, isTrue);
      final restoredPanel = cubit.state.activeBoard!.panels.single;
      expect(restoredPanel.title, 'Rhombus');
      expect(restoredPanel.bounds.width, 120);
      expect(restoredPanel.bounds.height, 120);
      expect(restoredPanel.state, {'shape': 'diamond'});
    },
  );

  test('undoLatestPanelHistory coalesces resize update bursts', () async {
    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board')],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    const panel = BoardPanelInstance(
      id: 'shape-1',
      type: 'board.shape',
      title: 'Rhombus',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 120, height: 120),
      state: {'shape': 'diamond'},
    );

    await cubit.addPanel(panel);
    await cubit.updatePanel(
      'shape-1',
      (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 160)),
    );
    await cubit.updatePanel(
      'shape-1',
      (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 220)),
    );
    await cubit.updatePanel(
      'shape-1',
      (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 280)),
    );

    final undone = await cubit.undoLatestPanelHistory('board');

    expect(undone, isTrue);
    final restoredPanel = cubit.state.activeBoard!.panels.single;
    expect(restoredPanel.bounds.width, 120);
    expect(restoredPanel.bounds.height, 120);

    final events = await cubit.historyForBoard('board');
    expect(events.last.type, 'panel.restored');
    expect(events.last.before!['bounds']['width'], 280);
    expect(events.last.after!['bounds']['width'], 120);
  });

  test(
    'undoLatestPanelHistory undoes only the latest semantic batch',
    () async {
      final historyStore = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
      addTearDown(cubit.close);
      cubit.emit(
        const BoardState(
          boards: [BoardDocument(id: 'board', name: 'Board')],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      const panel = BoardPanelInstance(
        id: 'shape-1',
        type: 'board.shape',
        title: 'Rhombus',
        bounds: BoardPanelBounds(x: 10, y: 20, width: 120, height: 120),
        state: {'shape': 'diamond', 'text': 'before'},
      );

      await cubit.addPanel(panel);
      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 180)),
      );
      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(bounds: panel.bounds.copyWith(width: 240)),
      );
      await cubit.updatePanel(
        'shape-1',
        (panel) => panel.copyWith(state: {...panel.state, 'text': 'after'}),
      );

      final firstUndo = await cubit.undoLatestPanelHistory('board');
      final afterTextUndo = cubit.state.activeBoard!.panels.single;
      final secondUndo = await cubit.undoLatestPanelHistory('board');
      final afterResizeUndo = cubit.state.activeBoard!.panels.single;

      expect(firstUndo, isTrue);
      expect(afterTextUndo.state['text'], 'before');
      expect(afterTextUndo.bounds.width, 240);
      expect(secondUndo, isTrue);
      expect(afterResizeUndo.bounds.width, 120);
    },
  );

  test('undoLatestPanelHistory removes a just-created panel', () async {
    final historyStore = MemoryBoardHistoryStore();
    final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
    addTearDown(cubit.close);
    cubit.emit(
      const BoardState(
        boards: [BoardDocument(id: 'board', name: 'Board')],
        activeBoardId: 'board',
        isLoaded: true,
      ),
    );

    const panel = BoardPanelInstance(
      id: 'panel-1',
      type: StickyNotePlugin.kTypeId,
      title: 'Sticky note',
      bounds: BoardPanelBounds(x: 10, y: 20, width: 240, height: 180),
      state: {'text': 'new draft'},
    );

    await cubit.addPanel(panel);

    final undone = await cubit.undoLatestPanelHistory('board');

    expect(undone, isTrue);
    expect(cubit.state.activeBoard!.panels, isEmpty);
  });

  test(
    'undoLatestPanelHistory returns false when there is no panel history',
    () async {
      final historyStore = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: historyStore, actorId: 'tester');
      addTearDown(cubit.close);
      cubit.emit(
        const BoardState(
          boards: [BoardDocument(id: 'board', name: 'Board')],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      final undone = await cubit.undoLatestPanelHistory('board');

      expect(undone, isFalse);
    },
  );
}
