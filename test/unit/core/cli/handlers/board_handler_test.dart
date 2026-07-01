import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/board_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

class _FakeRect extends Fake implements Rect {}

shelf.Request _getRequest(String path, {Map<String, String>? query}) {
  final uri = Uri.parse('http://localhost:8080$path').replace(queryParameters: query);
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

shelf.Request _deleteRequest(String path) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request('DELETE', uri);
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
  late _MockBoardCubit mockBoardCubit;
  late BoardDocument testBoard;
  var rebuildScheduled = false;

  setUpAll(() {
    registerFallbackValue(_FakeRect());
  });

  setUp(() {
    mockBoardCubit = _MockBoardCubit();
    rebuildScheduled = false;

    testBoard = const BoardDocument(
      id: 'b1',
      name: 'Test Board',
      panels: [
        BoardPanelInstance(
          id: 'p1',
          type: 'board.chat',
          title: 'Chat',
          bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
        ),
      ],
    );

    when(() => mockBoardCubit.state).thenReturn(
      BoardState(
        boards: [testBoard],
        activeBoardId: 'b1',
        isLoaded: true,
        selectedPanelIds: const {'p1'},
      ),
    );
    when(() => mockBoardCubit.deleteBoard(any())).thenAnswer((_) async {});
    when(() => mockBoardCubit.removeLink(any(), boardId: any(named: 'boardId')))
        .thenAnswer((_) async {});
    when(() => mockBoardCubit.selectPanels(any())).thenReturn(null);
    when(() => mockBoardCubit.selectPanelsInRect(any())).thenReturn(null);
  });

  group('handleBoard', () {
    test('GET /boards/:id returns board details', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        [],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () => rebuildScheduled = true,
        boardDetails: (board) {
          called = true;
          return _json({'id': board.id, 'name': board.name});
        },
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({'format': format}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('PUT /boards/:id updates board', () async {
      var called = false;
      final response = await handleBoard(
        'PUT',
        [],
        testBoard,
        mockBoardCubit,
        _putRequest('/api/boards/b1', body: {'name': 'Updated'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () => rebuildScheduled = true,
        boardDetails: (_) => _json({}),
        updateBoard: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('DELETE /boards/:id deletes board and schedules rebuild', () async {
      final response = await handleBoard(
        'DELETE',
        [],
        testBoard,
        mockBoardCubit,
        _deleteRequest('/api/boards/b1'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () => rebuildScheduled = true,
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(rebuildScheduled, true);
      verify(() => mockBoardCubit.deleteBoard('b1')).called(1);
    });

    test('GET /boards/:id/snapshot returns snapshot with format', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['snapshot'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/snapshot', query: {'format': 'json'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (board, {format = 'md'}) {
          called = true;
          return _json({'format': format});
        },
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['format'], 'json');
    });

    test('POST /boards/:id/apply calls applyYaml', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['apply'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/apply', body: {'panels': []}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (cubit, board, request) async {
          called = true;
          return _json({'ok': true});
        },
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('POST /boards/:id/undo calls undoBoard', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['undo'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/undo'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (cubit, board) async {
          called = true;
          return _json({'ok': true});
        },
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('POST /boards/:id/redo calls redoBoard', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['redo'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/redo'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (cubit, board) async {
          called = true;
          return _json({'ok': true});
        },
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('GET /boards/:id/screenshot with offscreen mode', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['screenshot'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/screenshot', query: {'mode': 'offscreen'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (board, {cubit, forceOffscreen = false}) async {
          called = true;
          return _json({'offscreen': forceOffscreen});
        },
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['offscreen'], true);
    });

    test('GET /boards/:id/panels returns panel list', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['panels'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/panels'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (board) {
          called = true;
          return _json({'panels': board.panels.length});
        },
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['panels'], 1);
    });

    test('POST /boards/:id/panels creates panel', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['panels'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/panels', body: {'type': 'board.note'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('GET /boards/:id/panels/:panelId routes to handlePanel', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['panels', 'p1', 'messages'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/panels/p1/messages'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (method, sub, board, panel, cubit, request) async {
          called = true;
          return _json({'panelId': panel.id});
        },
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['panelId'], 'p1');
    });

    test('GET /boards/:id/panels/unknown returns notFound', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['panels', 'unknown'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/panels/unknown'),
        body: _body,
        json: _json,
        error: _error,
        notFound: (msg) {
          called = true;
          return _notFound(msg);
        },
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 404);
      expect(called, true);
    });

    test('GET /boards/:id/links returns links', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['links'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/links'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (board) {
          called = true;
          return _json({'links': board.links.length});
        },
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('POST /boards/:id/links creates link', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['links'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/links', body: {'from': 'p1', 'to': 'p2'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('DELETE /boards/:id/links/:linkId deletes link', () async {
      final response = await handleBoard(
        'DELETE',
        ['links', 'l1'],
        testBoard,
        mockBoardCubit,
        _deleteRequest('/api/boards/b1/links/l1'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () => rebuildScheduled = true,
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(rebuildScheduled, true);
      verify(() => mockBoardCubit.removeLink('l1', boardId: 'b1')).called(1);
    });

    test('GET /boards/:id/panel-types returns types', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['panel-types'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/panel-types'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () {
          called = true;
          return _json({'types': []});
        },
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('PUT /boards/:id/viewport updates viewport', () async {
      var called = false;
      final response = await handleBoard(
        'PUT',
        ['viewport'],
        testBoard,
        mockBoardCubit,
        _putRequest('/api/boards/b1/viewport', body: {'scale': 1.5}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('POST /boards/:id/fit calls fitViewport', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['fit'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/fit'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('POST /boards/:id/arrange calls arrangeBoard', () async {
      var called = false;
      final response = await handleBoard(
        'POST',
        ['arrange'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/arrange'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (cubit, board, body) async {
          called = true;
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(called, true);
    });

    test('GET /boards/:id/select returns selected panel ids', () async {
      final response = await handleBoard(
        'GET',
        ['select'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/select'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      final payload = jsonDecode(await response.readAsString())
          as Map<String, dynamic>;
      expect(payload['ok'], true);
      expect(payload['selected'], const ['p1']);
    });

    test('POST /boards/:id/select selects panels by ids', () async {
      final response = await handleBoard(
        'POST',
        ['select'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/select', body: {'panels': 'p1,p2'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 200);
      verify(() => mockBoardCubit.selectPanels(const {'p1', 'p2'})).called(1);
    });

    test('POST /boards/:id/select rejects missing panels and rect', () async {
      final response = await handleBoard(
        'POST',
        ['select'],
        testBoard,
        mockBoardCubit,
        _postRequest('/api/boards/b1/select'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 400);
      verifyNever(() => mockBoardCubit.selectPanels(any()));
      verifyNever(() => mockBoardCubit.selectPanelsInRect(any()));
    });

    test('unknown route returns notFound', () async {
      var called = false;
      final response = await handleBoard(
        'GET',
        ['unknown'],
        testBoard,
        mockBoardCubit,
        _getRequest('/api/boards/b1/unknown'),
        body: _body,
        json: _json,
        error: _error,
        notFound: (msg) {
          called = true;
          return _notFound(msg);
        },
        scheduleRebuild: () {},
        boardDetails: (_) => _json({}),
        updateBoard: (_, __, ___) async => _json({}),
        boardSnapshot: (_, {format = 'md'}) => _json({}),
        applyYaml: (_, __, ___) async => _json({}),
        undoBoard: (_, __) async => _json({}),
        redoBoard: (_, __) async => _json({}),
        boardScreenshot: (_, {cubit, forceOffscreen = false}) async => _json({}),
        boardSvg: (_) => _json({}),
        listPanels: (_) => _json({}),
        createPanel: (_, __, ___) async => _json({}),
        handlePanel: (_, __, ___, ____, _____, ______) async => _json({}),
        listLinks: (_) => _json({}),
        createLink: (_, __, ___) async => _json({}),
        updateLink: (_, __, ___, ____) async => _json({}),
        listPanelTypes: () => _json({}),
        updateViewport: (_, __, ___) async => _json({}),
        fitViewport: (_, __, ___) async => _json({}),
        arrangeBoard: (_, __, ___) async => _json({}),
      );

      expect(response.statusCode, 404);
      expect(called, true);
    });
  });
}
