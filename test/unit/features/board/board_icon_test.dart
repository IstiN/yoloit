import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('BoardIconSpec.parse', () {
    test('auto/clear/none reset to null', () {
      expect(BoardIconSpec.parse('auto'), isNull);
      expect(BoardIconSpec.parse('clear'), isNull);
      expect(BoardIconSpec.parse('none'), isNull);
      expect(BoardIconSpec.parse(''), isNull);
    });

    test('emoji prefix', () {
      final spec = BoardIconSpec.parse('emoji:🚀');
      expect(spec, isNotNull);
      expect(spec!.kind, BoardIconSpec.kindEmoji);
      expect(spec.value, '🚀');
    });

    test('bare emoji', () {
      final spec = BoardIconSpec.parse('🎯');
      expect(spec, isNotNull);
      expect(spec!.kind, BoardIconSpec.kindEmoji);
    });

    test('builtin preset', () {
      final spec = BoardIconSpec.parse('builtin:yoloit');
      expect(spec, isNotNull);
      expect(spec!.kind, BoardIconSpec.kindBuiltin);
      expect(spec.value, 'yoloit');
    });

    test('unknown builtin throws', () {
      expect(
        () => BoardIconSpec.parse('builtin:nope'),
        throwsFormatException,
      );
    });

    test('file prefix and image path', () {
      final prefixed = BoardIconSpec.parse('file:/tmp/icon.png');
      expect(prefixed!.kind, BoardIconSpec.kindFile);
      expect(prefixed.value, '/tmp/icon.png');

      final plain = BoardIconSpec.parse('/tmp/my icon.jpg');
      expect(plain!.kind, BoardIconSpec.kindFile);
    });

    test('unparseable value throws', () {
      expect(
        () => BoardIconSpec.parse('not-an-icon-value'),
        throwsFormatException,
      );
    });
  });

  group('BoardIconSpec json', () {
    test('roundtrip', () {
      const spec = BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: '🚀');
      final restored = BoardIconSpec.fromJson(spec.toJson());
      expect(restored, spec);
    });

    test('invalid json returns null', () {
      expect(BoardIconSpec.fromJson(null), isNull);
      expect(BoardIconSpec.fromJson(const {}), isNull);
      expect(
        BoardIconSpec.fromJson(const {'kind': 'weird', 'value': 'x'}),
        isNull,
      );
    });

    test('describe', () {
      expect(
        const BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: '🚀')
            .describe(),
        'emoji:🚀',
      );
      expect(
        const BoardIconSpec(kind: BoardIconSpec.kindBuiltin, value: 'yoloit')
            .describe(),
        'builtin:yoloit',
      );
      expect(
        const BoardIconSpec(kind: BoardIconSpec.kindFile, value: '/a/b.png')
            .describe(),
        '/a/b.png',
      );
    });
  });

  group('BoardDocument icon metadata', () {
    test('icon getter reads metadata', () {
      const withIcon = BoardDocument(
        id: 'b',
        name: 'B',
        metadata: {
          'icon': {'kind': 'emoji', 'value': '🚀'},
        },
      );
      expect(withIcon.icon?.kind, BoardIconSpec.kindEmoji);
      expect(withIcon.icon?.value, '🚀');

      const without = BoardDocument(id: 'b', name: 'B');
      expect(without.icon, isNull);
    });

    test('copyWithIcon sets and clears metadata', () {
      const board = BoardDocument(id: 'b', name: 'B');
      const spec = BoardIconSpec(kind: BoardIconSpec.kindFile, value: '/i.png');

      final withIcon = board.copyWithIcon(spec);
      expect(withIcon.icon, spec);

      final cleared = withIcon.copyWithIcon(null);
      expect(cleared.icon, isNull);
      expect(cleared.metadata.containsKey('icon'), isFalse);
    });

    test('icon survives json roundtrip', () {
      const board = BoardDocument(
        id: 'b',
        name: 'B',
        metadata: {
          'icon': {'kind': 'builtin', 'value': 'yoloit'},
        },
      );
      final restored = BoardDocument.fromJson(board.toJson());
      expect(restored.icon?.kind, BoardIconSpec.kindBuiltin);
      expect(restored.icon?.value, 'yoloit');
    });
  });

  group('BoardCubit.updateBoardIcon', () {
    test('sets and clears icon override', () async {
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      const board = BoardDocument(id: 'board', name: 'Board');
      cubit.emit(
        const BoardState(
          boards: [board],
          activeBoardId: 'board',
          isLoaded: true,
        ),
      );

      const spec = BoardIconSpec(kind: BoardIconSpec.kindEmoji, value: '🚀');
      await cubit.updateBoardIcon('board', spec);
      expect(cubit.state.activeBoard!.icon, spec);

      await cubit.updateBoardIcon('board', null);
      expect(cubit.state.activeBoard!.icon, isNull);
    });
  });
}
