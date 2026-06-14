import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/group_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

shelf.Request _getRequest(String path) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request('GET', uri);
}

shelf.Request _postRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'POST',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Request _putRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'PUT',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Request _deleteRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'DELETE',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Response _json(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

shelf.Response _error(String msg) => shelf.Response(
  400,
  body: jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

shelf.Response _notFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

Future<Map<String, dynamic>> _body(shelf.Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  late _MockBoardCubit mockCubit;
  late BoardDocument board;
  var rebuildScheduled = false;

  setUp(() {
    mockCubit = _MockBoardCubit();
    rebuildScheduled = false;

    board = const BoardDocument(
      id: 'b1',
      name: 'Test Board',
      panels: [
        BoardPanelInstance(
          id: 'p1',
          type: 'board.chat',
          title: 'Chat',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
        ),
        BoardPanelInstance(
          id: 'p2',
          type: 'board.chat',
          title: 'Chat 2',
          bounds: BoardPanelBounds(x: 500, y: 0, width: 400, height: 300),
        ),
      ],
      groups: [
        BoardPanelGroup(id: 'g1', name: 'Alpha', panelIds: ['p1']),
      ],
    );

    when(() => mockCubit.state).thenReturn(
      BoardState(
        boards: [board],
        activeBoardId: 'b1',
        isLoaded: true,
      ),
    );
    when(
      () => mockCubit.createGroup(
        any(),
        name: any(named: 'name'),
        panelIds: any(named: 'panelIds'),
        color: any(named: 'color'),
      ),
    ).thenAnswer((_) async {});
    when(() => mockCubit.deleteGroup(any(), any())).thenAnswer((_) async {});
    when(() => mockCubit.renameGroup(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCubit.setGroupColor(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCubit.addPanelsToGroup(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCubit.removePanelsFromGroup(any(), any(), any()))
        .thenAnswer((_) async {});
    when(() => mockCubit.toggleGroupCollapse(any(), any()))
        .thenAnswer((_) async {});
  });

  Future<shelf.Response> handle(
    String method,
    List<String> sub,
    shelf.Request request,
  ) =>
      handleGroup(
        method,
        sub,
        board,
        mockCubit,
        request,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () => rebuildScheduled = true,
      );

  group('handleGroup', () {
    test('GET /groups lists groups', () async {
      final response = await handle('GET', [], _getRequest('/api/boards/b1/groups'));
      final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(payload['ok'], true);
      expect((payload['groups'] as List<dynamic>).length, 1);
    });

    test('POST /groups creates a group and schedules rebuild', () async {
      final response = await handle(
        'POST',
        [],
        _postRequest('/api/boards/b1/groups', body: {
          'name': 'Beta',
          'panels': ['p2'],
          'color': '#ff0000',
        }),
      );
      final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(payload['ok'], true);
      expect(rebuildScheduled, true);
      verify(
        () => mockCubit.createGroup(
          'b1',
          name: 'Beta',
          panelIds: ['p2'],
          color: 0xFFFF0000,
        ),
      ).called(1);
    });

    test('POST /groups rejects missing name', () async {
      final response = await handle(
        'POST',
        [],
        _postRequest('/api/boards/b1/groups', body: {'panels': 'p2'}),
      );

      expect(response.statusCode, 400);
      verifyNever(() => mockCubit.createGroup(any(), name: any(named: 'name')));
    });

    test('DELETE /groups/:id deletes group', () async {
      final response = await handle(
        'DELETE',
        ['g1'],
        _deleteRequest('/api/boards/b1/groups/g1'),
      );
      final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(payload['ok'], true);
      expect(rebuildScheduled, true);
      verify(() => mockCubit.deleteGroup('b1', 'g1')).called(1);
    });

    test('DELETE /groups/:id returns 404 for unknown group', () async {
      final response = await handle(
        'DELETE',
        ['gUnknown'],
        _deleteRequest('/api/boards/b1/groups/gUnknown'),
      );

      expect(response.statusCode, 404);
    });

    test('PUT /groups/:id renames and updates color', () async {
      final response = await handle(
        'PUT',
        ['g1'],
        _putRequest('/api/boards/b1/groups/g1', body: {
          'name': 'Gamma',
          'color': 'blue',
        }),
      );
      final payload = jsonDecode(await response.readAsString()) as Map<String, dynamic>;

      expect(response.statusCode, 200);
      expect(payload['ok'], true);
      verify(() => mockCubit.renameGroup('b1', 'g1', 'Gamma')).called(1);
      verify(() => mockCubit.setGroupColor('b1', 'g1', any())).called(1);
    });

    test('PUT /groups/:id toggles collapse when changed', () async {
      final response = await handle(
        'PUT',
        ['g1'],
        _putRequest('/api/boards/b1/groups/g1', body: {'collapsed': true}),
      );

      expect(response.statusCode, 200);
      verify(() => mockCubit.toggleGroupCollapse('b1', 'g1')).called(1);
    });

    test('POST /groups/:id/panels adds panels', () async {
      final response = await handle(
        'POST',
        ['g1', 'panels'],
        _postRequest('/api/boards/b1/groups/g1/panels', body: {
          'panels': 'p1,p2',
        }),
      );

      expect(response.statusCode, 200);
      verify(() => mockCubit.addPanelsToGroup('b1', 'g1', ['p1', 'p2']))
          .called(1);
    });

    test('DELETE /groups/:id/panels removes panels', () async {
      final response = await handle(
        'DELETE',
        ['g1', 'panels'],
        _deleteRequest('/api/boards/b1/groups/g1/panels', body: {
          'panels': ['p1'],
        }),
      );

      expect(response.statusCode, 200);
      verify(() => mockCubit.removePanelsFromGroup('b1', 'g1', ['p1']))
          .called(1);
    });

    test('POST /groups/:id/panels rejects empty panels', () async {
      final response = await handle(
        'POST',
        ['g1', 'panels'],
        _postRequest('/api/boards/b1/groups/g1/panels'),
      );

      expect(response.statusCode, 400);
      verifyNever(() => mockCubit.addPanelsToGroup(any(), any(), any()));
    });
  });
}
