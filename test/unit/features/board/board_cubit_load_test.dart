import 'dart:convert';

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

  group('BoardCubit.load', () {
    test('creates default board when no saved data', () async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isLoaded, true);
      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.name, 'Board 1');
      expect(cubit.state.activeBoardId, cubit.state.boards.first.id);
    });

    test('restores saved boards', () async {
      final board = BoardDocument(
        id: 'b1',
        name: 'Test Board',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Chat',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode([board.toJson()]);
      await prefs.setString('board.documents.v1', encoded);
      await prefs.setString('board.active.id.v1', 'b1');
      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isLoaded, true);
      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.name, 'Test Board');
      expect(cubit.state.boards.first.panels.length, 1);
      expect(cubit.state.activeBoardId, 'b1');
    });

    test('deduplicates duplicate panel IDs', () async {
      final board = BoardDocument(
        id: 'b1',
        name: 'Test',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Chat',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Duplicate',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('board.documents.v1', jsonEncode([board.toJson()]));
      await prefs.setString('board.active.id.v1', 'b1');

      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.boards.first.panels.length, 1);
    });

    test('removes stale links after deduplication', () async {
      final board = BoardDocument(
        id: 'b1',
        name: 'Test',
        panels: [
          BoardPanelInstance(
            id: 'p1',
            type: 'board.chat',
            title: 'Chat',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
        ],
        links: [
          BoardPanelLink(
            id: 'l1',
            fromPanelId: 'p1',
            toPanelId: 'p2',
          ),
        ],
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('board.documents.v1', jsonEncode([board.toJson()]));
      await prefs.setString('board.active.id.v1', 'b1');

      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.boards.first.links.isEmpty, true);
    });

    test('creates default board when saved list is empty', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('board.documents.v1', '[]');

      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isLoaded, true);
      expect(cubit.state.boards.length, 1);
      expect(cubit.state.boards.first.name, 'Board 1');
    });

    test('falls back to first board when active board ID is invalid', () async {
      final boards = [
        BoardDocument(
          id: 'b1',
          name: 'First',
          panels: [],
        ),
        BoardDocument(
          id: 'b2',
          name: 'Second',
          panels: [],
        ),
      ];
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'board.documents.v1',
        jsonEncode(boards.map((b) => b.toJson()).toList()),
      );
      await prefs.setString('board.active.id.v1', 'nonexistent');

      final cubit = BoardCubit();
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.activeBoardId, 'b1');
    });
  });
}
