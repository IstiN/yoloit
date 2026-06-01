import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/features/board/model/board_models.dart';

void main() {
  test('remote board snapshots do not include local viewport', () {
    const board = BoardDocument(
      id: 'local',
      name: 'Remote',
      viewport: BoardViewport(scale: 0.5, translation: Offset(120, -80)),
      metadata: {
        'remote': {'url': 'http://127.0.0.1:43110', 'boardId': 'remote-1'},
      },
    );

    final json = boardToRemoteJson(board);

    expect(json, isNot(contains('viewport')));
  });

  test('remote board hydration can preserve the local viewport', () {
    const localViewport = BoardViewport(
      scale: 1.8,
      translation: Offset(42, 24),
    );

    final board = remoteBoardFromJson(
      {
        'id': 'remote-1',
        'name': 'Remote',
        'viewport': {
          'scale': 0.5,
          'translation': {'dx': 100, 'dy': 200},
        },
        'panels': <Object?>[],
        'links': <Object?>[],
        'drawings': <Object?>[],
      },
      baseUrl: 'http://127.0.0.1:43110',
      viewportOverride: localViewport,
    );

    expect(board.viewport.scale, localViewport.scale);
    expect(board.viewport.translation, localViewport.translation);
  });
}
