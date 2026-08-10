import 'package:flutter/material.dart';
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

  group('remoteBoardFromJson links', () {
    BoardDocument hydrate(List<Object?> links) => remoteBoardFromJson(
          {
            'id': 'remote-1',
            'name': 'Remote',
            'panels': <Object?>[],
            'links': links,
            'drawings': <Object?>[],
          },
          baseUrl: 'http://127.0.0.1:43110',
        );

    test('parses links in the current schema', () {
      final board = hydrate([
        const BoardPanelLink(
          id: 'l1',
          fromPanelId: 'a',
          toPanelId: 'b',
          geometry: BoardLinkGeometry.straight,
        ).toJson(),
      ]);

      final link = board.links.single;
      expect(link.id, 'l1');
      expect(link.fromPanelId, 'a');
      expect(link.toPanelId, 'b');
      expect(link.geometry, BoardLinkGeometry.straight);
    });

    test('falls back to legacy from/to fields when parsing fails', () {
      final board = hydrate([
        {
          'from': 'p1',
          'to': 'p2',
          'style': 'line',
          'color': 0xFF112233,
          'geometry': 'elbow',
        },
      ]);

      final link = board.links.single;
      expect(link.fromPanelId, 'p1');
      expect(link.toPanelId, 'p2');
      expect(link.style, BoardLinkStyle.line);
      expect(link.color, const Color(0xFF112233));
      expect(link.geometry, BoardLinkGeometry.elbow);
      expect(link.id, isNotEmpty);
    });

    test('legacy links default to arrow style and bezier geometry', () {
      final board = hydrate([
        {'fromPanelId': 'p1', 'toPanelId': 'p2'},
      ]);

      final link = board.links.single;
      expect(link.style, BoardLinkStyle.arrow);
      expect(link.geometry, BoardLinkGeometry.bezier);
      expect(link.color, const Color(0xFF60A5FA));
    });

    test('drops legacy links missing an endpoint and non-map entries', () {
      final board = hydrate([
        {'fromPanelId': 'p1'},
        {'to': 'p2'},
        'not-a-map',
      ]);

      expect(board.links, isEmpty);
    });
  });
}
