import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BoardCubit operations', () {
    Future<BoardCubit> _createLoadedCubit({
      List<BoardDocument>? boards,
      String? activeBoardId,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      final docs = boards ??
          [
            BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'p1',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: const BoardPanelBounds(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
              ],
            ),
          ];
      await prefs.setString(
        'board.documents.v1',
        jsonEncode(docs.map((b) => b.toJson()).toList()),
      );
      await prefs.setString(
        'board.active.id.v1',
        activeBoardId ?? docs.first.id,
      );
      final cubit = BoardCubit();
      await cubit.load();
      return cubit;
    }

    test('setActiveBoard changes active board', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(id: 'b1', name: 'First', panels: []),
          BoardDocument(id: 'b2', name: 'Second', panels: []),
        ],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.setActiveBoard('b2');

      expect(cubit.state.activeBoardId, 'b2');
    });

    test('setActiveBoard ignores invalid board id', () async {
      final cubit = await _createLoadedCubit(
        boards: [BoardDocument(id: 'b1', name: 'First', panels: [])],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.setActiveBoard('invalid');

      expect(cubit.state.activeBoardId, 'b1');
    });

    test('renameBoard updates board name', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.renameBoard('b1', 'New Name');

      expect(cubit.state.boards.first.name, 'New Name');
    });

    test('renameBoard ignores empty name', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.renameBoard('b1', '   ');

      expect(cubit.state.boards.first.name, 'Board 1');
    });

    test('deleteBoard removes board', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(id: 'b1', name: 'First', panels: []),
          BoardDocument(id: 'b2', name: 'Second', panels: []),
        ],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.deleteBoard('b1');

      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.id, 'b2');
    });

    test('deleteBoard creates default when deleting last board', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.deleteBoard('b1');

      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.name, 'Board 1');
    });

    test('updateViewport updates board viewport', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      final newViewport = BoardViewport(
        scale: 2.0,
        translation: const Offset(100, 200),
      );
      await cubit.updateViewport(newViewport);

      expect(cubit.state.boards.first.viewport.scale, 2.0);
      expect(cubit.state.boards.first.viewport.translation.dx, 100);
    });

    test('focusPanel sets focused panel and bumps zIndex', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1');

      final board = cubit.state.boards.first;
      expect(board.viewport.focusedPanelId, 'p1');
      expect(board.panels.first.zIndex, greaterThan(0));
    });

    test('clearZoomFocus clears zoom flag', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1', zoomOnFocus: true);
      expect(cubit.state.boards.first.viewport.zoomOnFocus, true);

      await cubit.clearZoomFocus();

      expect(cubit.state.boards.first.viewport.zoomOnFocus, false);
    });

    test('clearFocusedPanel removes focused panel id', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1');
      expect(cubit.state.boards.first.viewport.focusedPanelId, 'p1');

      await cubit.clearFocusedPanel();

      expect(cubit.state.boards.first.viewport.focusedPanelId, isNull);
    });

    test('addPanel adds panel to board', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      final panel = BoardPanelInstance(
        id: 'p2',
        type: 'board.note',
        title: 'Note',
        bounds: const BoardPanelBounds(x: 10, y: 10, width: 200, height: 200),
      );
      await cubit.addPanel(panel);

      expect(cubit.state.boards.first.panels.length, 2);
    });

    test('removePanel removes panel and related links', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: const BoardPanelBounds(
                  x: 0,
                  y: 0,
                  width: 400,
                  height: 300,
                ),
              ),
              BoardPanelInstance(
                id: 'p2',
                type: 'board.note',
                title: 'Note',
                bounds: const BoardPanelBounds(
                  x: 10,
                  y: 10,
                  width: 200,
                  height: 200,
                ),
              ),
            ],
            links: [
              BoardPanelLink(
                id: 'l1',
                fromPanelId: 'p1',
                toPanelId: 'p2',
              ),
            ],
          ),
        ],
      );
      addTearDown(cubit.close);

      await cubit.removePanel('p2');

      expect(cubit.state.boards.first.panels.length, 1);
      expect(cubit.state.boards.first.links.isEmpty, true);
    });

    test('upsertLink creates new link', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: const BoardPanelBounds(
                  x: 0,
                  y: 0,
                  width: 400,
                  height: 300,
                ),
              ),
              BoardPanelInstance(
                id: 'p2',
                type: 'board.note',
                title: 'Note',
                bounds: const BoardPanelBounds(
                  x: 10,
                  y: 10,
                  width: 200,
                  height: 200,
                ),
              ),
            ],
          ),
        ],
      );
      addTearDown(cubit.close);

      final link = BoardPanelLink(
        id: 'l1',
        fromPanelId: 'p1',
        toPanelId: 'p2',
      );
      await cubit.upsertLink(link);

      expect(cubit.state.boards.first.links.length, 1);
      expect(cubit.state.boards.first.links.first.id, 'l1');
    });

    test('removeLink deletes link', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: const BoardPanelBounds(
                  x: 0,
                  y: 0,
                  width: 400,
                  height: 300,
                ),
              ),
            ],
            links: [
              BoardPanelLink(
                id: 'l1',
                fromPanelId: 'p1',
                toPanelId: 'p1',
              ),
            ],
          ),
        ],
      );
      addTearDown(cubit.close);

      await cubit.removeLink('l1');

      expect(cubit.state.boards.first.links.isEmpty, true);
    });

    test('updateBoardDefaultFolder sets and removes folder', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.updateBoardDefaultFolder('b1', '/projects');
      expect(
        cubit.state.boards.first.metadata['defaultFolder'],
        '/projects',
      );

      await cubit.updateBoardDefaultFolder('b1', null);
      expect(
        cubit.state.boards.first.metadata.containsKey('defaultFolder'),
        false,
      );
    });

    test('replaceBoardSnapshotFromShare replaces board content', () async {
      final cubit = await _createLoadedCubit(
        boards: [
          BoardDocument(id: 'b1', name: 'Old', panels: []),
        ],
      );
      addTearDown(cubit.close);

      final snapshot = BoardDocument(
        id: 'b1',
        name: 'New',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Chat',
            bounds: const BoardPanelBounds(
              x: 0,
              y: 0,
              width: 400,
              height: 300,
            ),
          ),
        ],
      );
      final result = await cubit.replaceBoardSnapshotFromShare(snapshot);

      expect(result, isNotNull);
      expect(cubit.state.boards.first.name, 'New');
      expect(cubit.state.boards.first.panels.length, 1);
    });

    test('replaceBoardSnapshotFromShare returns null for unknown id', () async {
      final cubit = await _createLoadedCubit();
      addTearDown(cubit.close);

      final snapshot = BoardDocument(id: 'unknown', name: 'New', panels: []);
      final result = await cubit.replaceBoardSnapshotFromShare(snapshot);

      expect(result, isNull);
    });
  });
}
