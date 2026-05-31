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
}
