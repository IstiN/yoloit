import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/history/board_history_store.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  BoardCubit buildCubit(List<BoardDocument> boards,
      {String activeBoardId = 'b1'}) {
    final cubit = BoardCubit(historyStore: MemoryBoardHistoryStore());
    addTearDown(cubit.close);
    cubit.emit(
      BoardState(
          boards: boards, activeBoardId: activeBoardId, isLoaded: true),
    );
    return cubit;
  }

  const drawing = BoardDrawingElement(
    id: 'd1',
    strokes: [],
    position: Offset(10, 20),
    size: Size(100, 50),
    strokeColor: Color(0xFFFFFFFF),
    strokeWidth: 2,
  );

  group('moveDrawing', () {
    test('moves the drawing to a new position', () async {
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        drawings: const [drawing],
      );
      final cubit = buildCubit([board]);

      await cubit.moveDrawing('d1', const Offset(50, 60));

      final updated = cubit.state.activeBoard!.drawings.single;
      expect(updated.position, const Offset(50, 60));
    });

    test('does nothing when there is no active board', () async {
      final cubit = BoardCubit(historyStore: MemoryBoardHistoryStore());
      addTearDown(cubit.close);
      cubit.emit(const BoardState(boards: [], isLoaded: true));

      // No active board — should not throw.
      await cubit.moveDrawing('d1', const Offset(50, 60));
    });

    test('records history when the drawing position changes', () async {
      final store = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: store);
      addTearDown(cubit.close);
      cubit.emit(
        BoardState(
          boards: [
            BoardDocument(
              id: 'b1',
              name: 'Board',
              drawings: const [drawing],
            ),
          ],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );

      await cubit.moveDrawing('d1', const Offset(100, 200));

      final events = await store.eventsForBoard('b1');
      expect(events, hasLength(1));
      expect(events.single.type, 'drawing.updated');
      expect(events.single.entityId, 'd1');
    });

    test('does not record history when drawing is unchanged', () async {
      final store = MemoryBoardHistoryStore();
      final cubit = BoardCubit(historyStore: store);
      addTearDown(cubit.close);
      cubit.emit(
        BoardState(
          boards: [
            BoardDocument(
              id: 'b1',
              name: 'Board',
              drawings: const [drawing],
            ),
          ],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );

      // Move to same position — should not create a history event.
      await cubit.moveDrawing('d1', const Offset(10, 20));

      final events = await store.eventsForBoard('b1');
      expect(events, isEmpty);
    });

    test('targets a specific board by id', () async {
      final board1 = BoardDocument(
        id: 'b1',
        name: 'Board 1',
        drawings: const [drawing],
      );
      final board2 = BoardDocument(
        id: 'b2',
        name: 'Board 2',
        drawings: const [drawing],
      );
      final cubit = buildCubit([board1, board2], activeBoardId: 'b1');

      await cubit.moveDrawing('d1', const Offset(99, 99), boardId: 'b2');

      final b2 = cubit.state.boards.firstWhere((b) => b.id == 'b2');
      expect(b2.drawings.single.position, const Offset(99, 99));

      final b1 = cubit.state.boards.firstWhere((b) => b.id == 'b1');
      expect(b1.drawings.single.position, const Offset(10, 20));
    });
  });

  group('resizeGroupCollapsedBounds', () {
    test('updates collapsed bounds and relayouts panels', () async {
      const panel1 = BoardPanelInstance(
        id: 'p1',
        type: 'board.shape',
        title: 'P1',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      );
      const panel2 = BoardPanelInstance(
        id: 'p2',
        type: 'board.shape',
        title: 'P2',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      );
      const group = BoardPanelGroup(
        id: 'g1',
        name: 'Group',
        panelIds: ['p1', 'p2'],
        collapsed: true,
      );
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: const [panel1, panel2],
        groups: const [group],
      );
      final cubit = buildCubit([board]);

      await cubit.resizeGroupCollapsedBounds(
        'b1',
        'g1',
        const BoardPanelBounds(x: 10, y: 10, width: 400, height: 300),
      );

      final updated = cubit.state.boards.single;
      final g = updated.groups.single;
      expect(g.collapsedBounds, isNotNull);
      expect(g.collapsedBounds!.width, 400);
    });

    test('is a no-op for a non-collapsed group', () async {
      const panel1 = BoardPanelInstance(
        id: 'p1',
        type: 'board.shape',
        title: 'P1',
        bounds: BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
      );
      const group = BoardPanelGroup(
        id: 'g1',
        name: 'Group',
        panelIds: ['p1'],
        collapsed: false,
      );
      final board = BoardDocument(
        id: 'b1',
        name: 'Board',
        panels: const [panel1],
        groups: const [group],
      );
      final cubit = buildCubit([board]);

      final originalBounds = cubit.state.boards.single.panels.single.bounds;
      await cubit.resizeGroupCollapsedBounds(
        'b1',
        'g1',
        const BoardPanelBounds(x: 10, y: 10, width: 400, height: 300),
      );

      // Panel bounds should not change for a non-collapsed group.
      expect(
        cubit.state.boards.single.panels.single.bounds,
        originalBounds,
      );
    });

    test('is a no-op for a missing group', () async {
      final board = BoardDocument(id: 'b1', name: 'Board');
      final cubit = buildCubit([board]);

      await cubit.resizeGroupCollapsedBounds(
        'b1',
        'missing',
        const BoardPanelBounds(x: 10, y: 10, width: 400, height: 300),
      );

      // Board is unchanged.
      expect(cubit.state.boards.single.groups, isEmpty);
    });
  });
}
