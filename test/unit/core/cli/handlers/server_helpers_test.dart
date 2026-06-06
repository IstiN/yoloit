import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  group('findBoard', () {
    final boardA = BoardDocument(
      id: 'board-a',
      name: 'Alpha',
      panels: const <BoardPanelInstance>[],
      links: const <BoardPanelLink>[],
    );
    final boardB = BoardDocument(
      id: 'board-b-long-id',
      name: 'Beta',
      panels: const <BoardPanelInstance>[],
      links: const <BoardPanelLink>[],
    );
    final cubit = BoardCubit()
      ..emit(BoardState(boards: [boardA, boardB], activeBoardId: 'board-a'));

    test('finds by exact id', () {
      expect(findBoard(cubit, 'board-a')?.id, 'board-a');
    });

    test('finds by name case-insensitive', () {
      expect(findBoard(cubit, 'alpha')?.id, 'board-a');
      expect(findBoard(cubit, 'ALPHA')?.id, 'board-a');
    });

    test('finds by id prefix', () {
      expect(findBoard(cubit, 'board-b')?.id, 'board-b-long-id');
    });

    test('returns null when nothing matches', () {
      expect(findBoard(cubit, 'gamma'), isNull);
    });
  });

  group('findPanel', () {
    final panel1 = BoardPanelInstance(
      id: 'p1',
      type: 'note',
      title: 'Notes',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
    );
    final panel2 = BoardPanelInstance(
      id: 'p2-extra',
      type: 'chat',
      title: 'Chat',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 100, height: 100),
    );
    final board = BoardDocument(
      id: 'b1',
      name: 'B',
      panels: [panel1, panel2],
      links: const <BoardPanelLink>[],
    );

    test('finds by exact id', () {
      expect(findPanel(board, 'p1')?.id, 'p1');
    });

    test('finds by title case-insensitive', () {
      expect(findPanel(board, 'chat')?.id, 'p2-extra');
      expect(findPanel(board, 'CHAT')?.id, 'p2-extra');
    });

    test('finds by id prefix', () {
      expect(findPanel(board, 'p2')?.id, 'p2-extra');
    });

    test('returns null when nothing matches', () {
      expect(findPanel(board, 'missing'), isNull);
    });
  });

  group('okJson / errorJson / missingField / missingFields / unknownRoute', () {
    test('okJson wraps extra', () {
      expect(okJson(<String, dynamic>{'id': 'x'}), <String, dynamic>{
        'ok': true,
        'id': 'x',
      });
    });

    test('okJson without extra', () {
      expect(okJson(), <String, dynamic>{'ok': true});
    });

    test('errorJson includes message and extra', () {
      expect(
        errorJson('bad', extra: <String, dynamic>{'code': 1}),
        <String, dynamic>{'ok': false, 'message': 'bad', 'code': 1},
      );
    });

    test('missingField formats field name', () {
      expect(missingField('id'), 'Missing "id" field');
    });

    test('missingFields joins list', () {
      expect(
        missingFields(const ['a', 'b']),
        'Missing required fields: a, b',
      );
    });

    test('unknownRoute formats route', () {
      expect(unknownRoute('widgets'), 'Unknown widgets route');
    });
  });

  group('parseColor', () {
    test('null returns null', () {
      expect(parseColor(null), isNull);
    });

    test('clear returns null', () {
      expect(parseColor('clear'), isNull);
    });

    test('6-digit hex gets full opacity', () {
      expect(parseColor('#FF0000'), const Color(0xFFFF0000));
    });

    test('8-digit hex uses alpha', () {
      expect(parseColor('#80FF0000'), const Color(0x80FF0000));
    });

    test('named colors', () {
      expect(parseColor('red'), const Color(0xFFFF4444));
      expect(parseColor('blue'), const Color(0xFF4488FF));
      expect(parseColor('WHITE'), const Color(0xFFF3F4F6));
    });

    test('unknown returns blue', () {
      expect(parseColor('blorg'), Colors.blue);
    });
  });
}
