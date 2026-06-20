import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('BoardCubit operations', () {
    Future<BoardCubit> createLoadedCubit({
      List<BoardDocument>? boards,
      String? activeBoardId,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      final docs =
          boards ??
          [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'p1',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
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
      final cubit = await createLoadedCubit(
        boards: [
          const BoardDocument(id: 'b1', name: 'First', panels: []),
          const BoardDocument(id: 'b2', name: 'Second', panels: []),
        ],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.setActiveBoard('b2');

      expect(cubit.state.activeBoardId, 'b2');
    });

    test('setActiveBoard ignores invalid board id', () async {
      final cubit = await createLoadedCubit(
        boards: [const BoardDocument(id: 'b1', name: 'First', panels: [])],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.setActiveBoard('invalid');

      expect(cubit.state.activeBoardId, 'b1');
    });

    test('renameBoard updates board name', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.renameBoard('b1', 'New Name');

      expect(cubit.state.boards.first.name, 'New Name');
    });

    test('renameBoard ignores empty name', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.renameBoard('b1', '   ');

      expect(cubit.state.boards.first.name, 'Board 1');
    });

    test('deleteBoard removes board', () async {
      final cubit = await createLoadedCubit(
        boards: [
          const BoardDocument(id: 'b1', name: 'First', panels: []),
          const BoardDocument(id: 'b2', name: 'Second', panels: []),
        ],
        activeBoardId: 'b1',
      );
      addTearDown(cubit.close);

      await cubit.deleteBoard('b1');

      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.id, 'b2');
    });

    test('deleteBoard creates default when deleting last board', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.deleteBoard('b1');

      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.name, 'Board 1');
    });

    test('updateViewport updates board viewport', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      const newViewport = BoardViewport(
        scale: 2.0,
        translation: Offset(100, 200),
      );
      await cubit.updateViewport(newViewport);

      expect(cubit.state.boards.first.viewport.scale, 2.0);
      expect(cubit.state.boards.first.viewport.translation.dx, 100);
    });

    test('focusPanel sets focused panel and bumps zIndex', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1');

      final board = cubit.state.boards.first;
      expect(board.viewport.focusedPanelId, 'p1');
      expect(board.panels.first.zIndex, greaterThan(0));
    });

    test('clearZoomFocus clears zoom flag', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1', zoomOnFocus: true);
      expect(cubit.state.boards.first.viewport.zoomOnFocus, true);

      await cubit.clearZoomFocus();

      expect(cubit.state.boards.first.viewport.zoomOnFocus, false);
    });

    test('clearFocusedPanel removes focused panel id', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.focusPanel('p1');
      expect(cubit.state.boards.first.viewport.focusedPanelId, 'p1');

      await cubit.clearFocusedPanel();

      expect(cubit.state.boards.first.viewport.focusedPanelId, isNull);
    });

    test('addPanel adds panel to board', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      const panel = BoardPanelInstance(
        id: 'p2',
        type: 'board.note',
        title: 'Note',
        bounds: BoardPanelBounds(x: 10, y: 10, width: 200, height: 200),
      );
      await cubit.addPanel(panel);

      expect(cubit.state.boards.first.panels.length, 2);
    });

    test('removePanel removes panel and related links', () async {
      final cubit = await createLoadedCubit(
        boards: [
          const BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
              ),
              BoardPanelInstance(
                id: 'p2',
                type: 'board.note',
                title: 'Note',
                bounds: BoardPanelBounds(x: 10, y: 10, width: 200, height: 200),
              ),
            ],
            links: [
              BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2'),
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
      final cubit = await createLoadedCubit(
        boards: [
          const BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
              ),
              BoardPanelInstance(
                id: 'p2',
                type: 'board.note',
                title: 'Note',
                bounds: BoardPanelBounds(x: 10, y: 10, width: 200, height: 200),
              ),
            ],
          ),
        ],
      );
      addTearDown(cubit.close);

      const link = BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p2');
      await cubit.upsertLink(link);

      expect(cubit.state.boards.first.links.length, 1);
      expect(cubit.state.boards.first.links.first.id, 'l1');
    });

    test('removeLink deletes link', () async {
      final cubit = await createLoadedCubit(
        boards: [
          const BoardDocument(
            id: 'b1',
            name: 'Board 1',
            panels: [
              BoardPanelInstance(
                id: 'p1',
                type: 'board.chat',
                title: 'Chat',
                bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
              ),
            ],
            links: [
              BoardPanelLink(id: 'l1', fromPanelId: 'p1', toPanelId: 'p1'),
            ],
          ),
        ],
      );
      addTearDown(cubit.close);

      await cubit.removeLink('l1');

      expect(cubit.state.boards.first.links.isEmpty, true);
    });

    test('updateBoardDefaultFolder sets and removes folder', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      await cubit.updateBoardDefaultFolder('b1', '/projects');
      expect(cubit.state.boards.first.metadata['defaultFolder'], '/projects');

      await cubit.updateBoardDefaultFolder('b1', null);
      expect(
        cubit.state.boards.first.metadata.containsKey('defaultFolder'),
        false,
      );
    });

    test('replaceBoardSnapshotFromShare replaces board content', () async {
      final cubit = await createLoadedCubit(
        boards: [const BoardDocument(id: 'b1', name: 'Old', panels: [])],
      );
      addTearDown(cubit.close);

      const snapshot = BoardDocument(
        id: 'b1',
        name: 'New',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Chat',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
        ],
      );
      final result = await cubit.replaceBoardSnapshotFromShare(snapshot);

      expect(result, isNotNull);
      expect(cubit.state.boards.first.name, 'New');
      expect(cubit.state.boards.first.panels.length, 1);
    });

    test('replaceBoardSnapshotFromShare returns null for unknown id', () async {
      final cubit = await createLoadedCubit();
      addTearDown(cubit.close);

      const snapshot = BoardDocument(id: 'unknown', name: 'New', panels: []);
      final result = await cubit.replaceBoardSnapshotFromShare(snapshot);

      expect(result, isNull);
    });

    group('grid view', () {
      test('setGridMode enables grid and arranges panels in a cloud', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.setGridMode('b1', enabled: true);

        expect(cubit.state.boards.first.gridMode.enabled, isTrue);
        expect(cubit.state.boards.first.panels.first.bounds.x, 0.0);
      });

      test('setGridMode restores freeform bounds when disabled', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        final originalBounds = cubit.state.boards.first.panels.first.bounds;
        await cubit.setGridMode('b1', enabled: true);
        expect(
          cubit.state.boards.first.panels.first.bounds,
          isNot(originalBounds),
        );

        await cubit.setGridMode('b1', enabled: false);

        expect(cubit.state.boards.first.gridMode.enabled, isFalse);
        expect(cubit.state.boards.first.panels.first.bounds, originalBounds);
      });

      test(
        'arrangePanelsByTypeInGrid groups panels into type blocks',
        () async {
          final cubit = await createLoadedCubit(
            boards: [
              const BoardDocument(
                id: 'b1',
                name: 'Board 1',
                panels: [
                  BoardPanelInstance(
                    id: 'note',
                    type: 'board.note.markdown',
                    title: 'Note',
                    bounds: BoardPanelBounds(
                      x: 1000,
                      y: 1000,
                      width: 220,
                      height: 220,
                    ),
                  ),
                  BoardPanelInstance(
                    id: 'chat',
                    type: 'board.chat',
                    title: 'Chat',
                    bounds: BoardPanelBounds(
                      x: 0,
                      y: 0,
                      width: 220,
                      height: 220,
                    ),
                  ),
                ],
              ),
            ],
          );
          addTearDown(cubit.close);
          await cubit.setGridMode('b1', enabled: true);

          await cubit.arrangePanelsByTypeInGrid('b1');

          final panels = cubit.state.boards.first.panels;
          final chat = panels.firstWhere((p) => p.id == 'chat');
          final note = panels.firstWhere((p) => p.id == 'note');
          expect(chat.bounds.y, 0.0);
          expect(note.bounds.y, 0.0);
          expect((chat.bounds.x - note.bounds.x).abs(), 488.0);
        },
      );

      test('arrangePanelsInGrid lays panels out in a cloud', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'note',
                  type: 'board.note.markdown',
                  title: 'Note',
                  bounds: BoardPanelBounds(
                    x: 1000,
                    y: 1000,
                    width: 220,
                    height: 220,
                  ),
                ),
                BoardPanelInstance(
                  id: 'chat',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: BoardPanelBounds(x: 0, y: 0, width: 220, height: 220),
                ),
              ],
            ),
          ],
        );
        addTearDown(cubit.close);
        await cubit.setGridMode('b1', enabled: true);

        await cubit.arrangePanelsInGrid('b1');

        final panels = cubit.state.boards.first.panels;
        final chat = panels.firstWhere((p) => p.id == 'chat');
        final note = panels.firstWhere((p) => p.id == 'note');
        expect(chat.bounds.y, 0.0);
        expect(note.bounds.y, 0.0);
        expect((chat.bounds.x - note.bounds.x).abs(), 244.0);
      });

      test(
        'resetGridView restores original layout and re-snaps to cloud',
        () async {
          final cubit = await createLoadedCubit(
            boards: [
              const BoardDocument(
                id: 'b1',
                name: 'Board 1',
                panels: [
                  BoardPanelInstance(
                    id: 'a',
                    type: 'board.note.markdown',
                    title: 'A',
                    bounds: BoardPanelBounds(
                      x: 0,
                      y: 0,
                      width: 220,
                      height: 220,
                    ),
                  ),
                  BoardPanelInstance(
                    id: 'b',
                    type: 'board.note.markdown',
                    title: 'B',
                    bounds: BoardPanelBounds(
                      x: 600,
                      y: 0,
                      width: 220,
                      height: 220,
                    ),
                  ),
                ],
              ),
            ],
          );
          addTearDown(cubit.close);
          await cubit.setGridMode('b1', enabled: true);
          await cubit.movePanelInGrid('b1', 'a', deltaCol: 2, deltaRow: 0);

          await cubit.resetGridView('b1');

          final panels = cubit.state.boards.first.panels;
          final a = panels.firstWhere((p) => p.id == 'a');
          final b = panels.firstWhere((p) => p.id == 'b');
          expect(a.bounds.x, 0.0);
          expect(b.bounds.x, greaterThan(0.0));
        },
      );

      test('movePanelInGrid pushes overlapping panel', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'a',
                  type: 'board.note.markdown',
                  title: 'A',
                  bounds: BoardPanelBounds(x: 0, y: 0, width: 220, height: 220),
                ),
                BoardPanelInstance(
                  id: 'b',
                  type: 'board.note.markdown',
                  title: 'B',
                  bounds: BoardPanelBounds(
                    x: 244,
                    y: 0,
                    width: 220,
                    height: 220,
                  ),
                ),
              ],
            ),
          ],
        );
        addTearDown(cubit.close);
        await cubit.setGridMode('b1', enabled: true);

        await cubit.movePanelInGrid('b1', 'a', deltaCol: 1, deltaRow: 0);

        final panels = cubit.state.boards.first.panels;
        final a = panels.firstWhere((p) => p.id == 'a');
        final b = panels.firstWhere((p) => p.id == 'b');
        expect(a.bounds.x, 244.0);
        expect(b.bounds.x, 488.0);
      });

      test('placePanelInGrid snaps and pushes on drop', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'a',
                  type: 'board.note.markdown',
                  title: 'A',
                  bounds: BoardPanelBounds(
                    x: 10,
                    y: 10,
                    width: 220,
                    height: 220,
                  ),
                ),
                BoardPanelInstance(
                  id: 'b',
                  type: 'board.note.markdown',
                  title: 'B',
                  bounds: BoardPanelBounds(
                    x: 244,
                    y: 0,
                    width: 220,
                    height: 220,
                  ),
                ),
              ],
            ),
          ],
        );
        addTearDown(cubit.close);
        await cubit.setGridMode('b1', enabled: true);

        // Simulate a smooth drag that dropped panel a on top of panel b.
        await cubit.movePanel('a', const Offset(234, -10));
        await cubit.placePanelInGrid('b1', 'a');

        final panels = cubit.state.boards.first.panels;
        final a = panels.firstWhere((p) => p.id == 'a');
        final b = panels.firstWhere((p) => p.id == 'b');
        expect(a.bounds.x, 244.0);
        expect(b.bounds.x, 488.0);
      });

      test('resizePanelInGrid snaps size to cells', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);
        await cubit.setGridMode('b1', enabled: true);

        await cubit.resizePanelInGrid(
          'p1',
          deltaCols: 1,
          deltaRows: 0,
          boardId: 'b1',
        );

        final panel = cubit.state.boards.first.panels.first;
        expect(panel.bounds.width, 708.0); // 3 cells + 2 spacings
      });

      test('new panel is placed on grid when grid mode is enabled', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);
        await cubit.setGridMode('b1', enabled: true);

        await cubit.createMarkdownNote(title: 'Note', markdown: 'text');

        final note = cubit.state.boards.first.panels.last;
        expect(note.bounds.x % 244, 0.0);
        expect(note.bounds.y % 244, 0.0);
      });
    });

    group('Groups', () {
      test('createGroup adds group with panels', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup(
          'b1',
          name: 'Research',
          panelIds: const ['p1'],
          color: 0xFF3B82F6,
        );

        final board = cubit.state.boards.first;
        expect(board.groups, hasLength(1));
        final group = board.groups.first;
        expect(group.name, 'Research');
        expect(group.panelIds, const ['p1']);
        expect(group.color, 0xFF3B82F6);
        expect(group.collapsed, false);
      });

      test('deleteGroup removes group and shows hidden panels', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1']);
        final groupId = cubit.state.boards.first.groups.first.id;
        final originalBounds = cubit.state.boards.first.panels.first.bounds;
        await cubit.toggleGroupCollapse('b1', groupId);
        expect(cubit.state.boards.first.panels.first.hidden, isFalse);
        expect(
          cubit.state.boards.first.panels.first.bounds.width,
          152,
        );

        await cubit.deleteGroup('b1', groupId);

        final board = cubit.state.boards.first;
        expect(board.groups, isEmpty);
        expect(board.panels.first.hidden, false);
        expect(board.panels.first.bounds, originalBounds);
      });

      test('renameGroup updates name', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'Old');
        final groupId = cubit.state.boards.first.groups.first.id;

        await cubit.renameGroup('b1', groupId, 'New');

        expect(cubit.state.boards.first.groups.first.name, 'New');
      });

      test('setGroupColor updates color', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', color: 0xFF000000);
        final groupId = cubit.state.boards.first.groups.first.id;

        await cubit.setGroupColor('b1', groupId, null);

        expect(cubit.state.boards.first.groups.first.color, isNull);
      });

      test('addPanelsToGroup moves panel from another group', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'p1',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: BoardPanelBounds(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
                BoardPanelInstance(
                  id: 'p2',
                  type: 'board.note.markdown',
                  title: 'Notes',
                  bounds: BoardPanelBounds(
                    x: 500,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
              ],
            ),
          ],
        );
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'A', panelIds: const ['p1']);
        await cubit.createGroup('b1', name: 'B', panelIds: const ['p2']);
        final groupB = cubit.state.boards.first.groups[1];

        await cubit.addPanelsToGroup('b1', groupB.id, const ['p1']);

        final board = cubit.state.boards.first;
        expect(board.groups[0].panelIds, isEmpty);
        expect(board.groups[1].panelIds, const ['p2', 'p1']);
      });

      test('removePanelsFromGroup restores visibility when collapsed', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1']);
        final groupId = cubit.state.boards.first.groups.first.id;
        final originalBounds = cubit.state.boards.first.panels.first.bounds;
        await cubit.toggleGroupCollapse('b1', groupId);

        await cubit.removePanelsFromGroup('b1', groupId, const ['p1']);

        final board = cubit.state.boards.first;
        expect(board.groups.first.panelIds, isEmpty);
        expect(board.panels.first.hidden, false);
        expect(board.panels.first.bounds, originalBounds);
      });

      test('toggleGroupCollapse stacks visible panels and restores bounds',
          () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1']);
        final groupId = cubit.state.boards.first.groups.first.id;
        final originalBounds = cubit.state.boards.first.panels.first.bounds;

        await cubit.toggleGroupCollapse('b1', groupId);
        expect(cubit.state.boards.first.panels.first.hidden, isFalse);
        expect(cubit.state.boards.first.groups.first.collapsed, true);
        expect(
          cubit.state.boards.first.panels.first.bounds.width,
          152,
        );

        await cubit.toggleGroupCollapse('b1', groupId);
        expect(cubit.state.boards.first.panels.first.hidden, false);
        expect(cubit.state.boards.first.groups.first.collapsed, false);
        expect(cubit.state.boards.first.panels.first.bounds, originalBounds);
      });

      Future<BoardCubit> createTwoPanelCubitForGroups() async {
        return createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'p1',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: BoardPanelBounds(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
                BoardPanelInstance(
                  id: 'p2',
                  type: 'board.note.markdown',
                  title: 'Notes',
                  bounds: BoardPanelBounds(
                    x: 100,
                    y: 100,
                    width: 400,
                    height: 300,
                  ),
                ),
              ],
            ),
          ],
        );
      }

      test('moveGroup moves every panel in the group', () async {
        final cubit = await createTwoPanelCubitForGroups();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1', 'p2']);
        final group = cubit.state.boards.first.groups.first;
        await cubit.moveGroup('b1', group.id, const Offset(10, 20));

        final board = cubit.state.boards.first;
        final p1 = board.panels.firstWhere((p) => p.id == 'p1');
        final p2 = board.panels.firstWhere((p) => p.id == 'p2');
        expect(p1.bounds.x, 10);
        expect(p1.bounds.y, 20);
        expect(p2.bounds.x, 110);
        expect(p2.bounds.y, 120);
      });

      test('toggleGroupCollapse stacks visible panels and sets focus', () async {
        final cubit = await createTwoPanelCubitForGroups();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1', 'p2']);
        final group = cubit.state.boards.first.groups.first;
        await cubit.toggleGroupCollapse('b1', group.id);

        final board = cubit.state.boards.first;
        final collapsed = board.groups.first;
        expect(collapsed.collapsed, isTrue);
        expect(collapsed.collapsedFocusPanelId, isNotNull);
        expect(board.panels.every((p) => !p.hidden), isTrue);
        expect(
          board.panels.every(
            (p) => p.bounds.width == 152 && p.bounds.height == 112,
          ),
          isTrue,
        );
      });

      test('cycleGroupFocus switches focused panel without expanding group',
          () async {
        final cubit = await createTwoPanelCubitForGroups();
        addTearDown(cubit.close);

        await cubit.createGroup('b1', name: 'G', panelIds: const ['p1', 'p2']);
        final group = cubit.state.boards.first.groups.first;
        await cubit.toggleGroupCollapse('b1', group.id);
        final firstFocus = cubit.state.boards.first.groups.first
            .collapsedFocusPanelId;

        await cubit.cycleGroupFocus('b1', group.id, 1);
        final secondFocus = cubit.state.boards.first.groups.first
            .collapsedFocusPanelId;

        expect(secondFocus, isNot(firstFocus));
        expect(cubit.state.boards.first.groups.first.collapsed, isTrue);
        expect(cubit.state.boards.first.panels.every((p) => !p.hidden), isTrue);
      });
    });

    group('Selection', () {
      Future<BoardCubit> _createTwoPanelCubit() async {
        return createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [
                BoardPanelInstance(
                  id: 'p1',
                  type: 'board.chat',
                  title: 'Chat',
                  bounds: BoardPanelBounds(
                    x: 0,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
                BoardPanelInstance(
                  id: 'p2',
                  type: 'board.note.markdown',
                  title: 'Notes',
                  bounds: BoardPanelBounds(
                    x: 500,
                    y: 0,
                    width: 400,
                    height: 300,
                  ),
                ),
              ],
            ),
          ],
        );
      }

      test('selectPanels updates selected set', () async {
        final cubit = await _createTwoPanelCubit();
        addTearDown(cubit.close);

        cubit.selectPanels(const {'p1'});

        expect(cubit.state.selectedPanelIds, const {'p1'});
      });

      test('togglePanelSelection adds and removes', () async {
        final cubit = await _createTwoPanelCubit();
        addTearDown(cubit.close);

        cubit.togglePanelSelection('p1');
        expect(cubit.state.selectedPanelIds, const {'p1'});

        cubit.togglePanelSelection('p2');
        expect(cubit.state.selectedPanelIds, const {'p1', 'p2'});

        cubit.togglePanelSelection('p1');
        expect(cubit.state.selectedPanelIds, const {'p2'});
      });

      test('clearSelection empties set', () async {
        final cubit = await _createTwoPanelCubit();
        addTearDown(cubit.close);

        cubit.selectPanels(const {'p1', 'p2'});
        cubit.clearSelection();

        expect(cubit.state.selectedPanelIds, isEmpty);
      });

      test('selectPanelsInRect selects overlapping panels', () async {
        final cubit = await _createTwoPanelCubit();
        addTearDown(cubit.close);

        cubit.selectPanelsInRect(
          const Rect.fromLTWH(0, 0, 450, 400),
        );

        expect(cubit.state.selectedPanelIds, const {'p1'});
      });

      test('setActiveBoard clears selection', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(id: 'b1', name: 'First', panels: []),
            const BoardDocument(id: 'b2', name: 'Second', panels: []),
          ],
          activeBoardId: 'b1',
        );
        addTearDown(cubit.close);

        cubit.selectPanels(const {'p1'});
        await cubit.setActiveBoard('b2');

        expect(cubit.state.selectedPanelIds, isEmpty);
      });

      test('createGroupFromSelection creates group and clears selection',
          () async {
        final cubit = await _createTwoPanelCubit();
        addTearDown(cubit.close);

        cubit.selectPanels(const {'p1', 'p2'});
        await cubit.createGroupFromSelection(name: 'Selected');

        final board = cubit.state.boards.first;
        expect(board.groups, hasLength(1));
        expect(board.groups.first.name, 'Selected');
        expect(
          board.groups.first.panelIds.toSet(),
          const {'p1', 'p2'},
        );
        expect(cubit.state.selectedPanelIds, isEmpty);
      });
    });

    group('archiveBoard', () {
      test('archiving a board excludes it from activeBoards', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(id: 'b1', name: 'First', panels: []),
            const BoardDocument(id: 'b2', name: 'Second', panels: []),
          ],
          activeBoardId: 'b1',
        );
        addTearDown(cubit.close);

        await cubit.archiveBoard('b1');

        expect(cubit.state.activeBoards.map((b) => b.id), ['b2']);
        expect(cubit.state.archivedBoards.map((b) => b.id), ['b1']);
      });

      test('archiving active board switches active to next unarchived', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(id: 'b1', name: 'First', panels: []),
            const BoardDocument(id: 'b2', name: 'Second', panels: []),
          ],
          activeBoardId: 'b1',
        );
        addTearDown(cubit.close);

        await cubit.archiveBoard('b1');

        expect(cubit.state.activeBoardId, 'b2');
      });

      test('unarchiveBoard restores board to activeBoards', () async {
        final cubit = await createLoadedCubit(
          boards: [
            const BoardDocument(
              id: 'b1',
              name: 'First',
              panels: [],
              archived: true,
            ),
            const BoardDocument(id: 'b2', name: 'Second', panels: []),
          ],
          activeBoardId: 'b2',
        );
        addTearDown(cubit.close);

        await cubit.unarchiveBoard('b1');

        expect(cubit.state.activeBoards.length, 2);
        expect(cubit.state.archivedBoards, isEmpty);
      });
    });

    group('createBoardFromOperations', () {
      test('creates a board with panels from template operations', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        final board = await cubit.createBoardFromOperations(
          name: 'From Template',
          operations: [
            {
              'op': 'panel.create',
              'type': 'board.note.markdown',
              'title': 'Notes',
              'x': 10.0,
              'y': 20.0,
              'width': 300.0,
              'height': 200.0,
            },
            {
              'op': 'panel.create',
              'type': 'board.checklist',
              'title': 'Tasks',
              'state': {'items': <dynamic>[]},
            },
          ],
        );

        expect(board, isNotNull);
        expect(board!.name, 'From Template');
        expect(board.panels.length, 2);
        expect(board.panels.first.title, 'Notes');
        expect(board.panels.first.type, 'board.note.markdown');
        expect(board.panels.last.title, 'Tasks');
        expect(board.panels.last.type, 'board.checklist');
      });

      test('creates an empty board when no operations are provided', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        final initialCount = cubit.state.boards.length;
        final board = await cubit.createBoardFromOperations(
          name: 'Empty Template',
          operations: [],
        );

        expect(board, isNotNull);
        expect(cubit.state.boards.length, initialCount + 1);
        expect(board!.panels, isEmpty);
      });

      test('applies board.configure to set default folder', () async {
        final cubit = await createLoadedCubit();
        addTearDown(cubit.close);

        final board = await cubit.createBoardFromOperations(
          name: 'Configured Template',
          operations: [
            {'op': 'board.configure', 'defaultFolder': '/projects'},
            {
              'op': 'panel.create',
              'type': 'board.note.markdown',
              'title': 'Note',
            },
          ],
        );

        expect(board, isNotNull);
        expect(board!.defaultFolder, '/projects');
      });
    });
  });
}
