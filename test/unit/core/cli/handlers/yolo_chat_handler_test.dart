import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/yolo_chat_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

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

  setUp(() {
    mockBoardCubit = _MockBoardCubit();

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
  });

  group('handleYoloChat', () {
    test('GET /yolochat/panels lists chat panels', () async {
      final response = await handleYoloChat(
        'GET',
        ['panels'],
        _getRequest('/api/yolochat/panels'),
        mockBoardCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        panelAction: (_, _, _, _) async => _json({}),
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(
        body['items'],
        const [
          {
            'boardId': 'b1',
            'boardName': 'Test Board',
            'panelId': 'p1',
            'panelTitle': 'Chat',
          },
        ],
      );
    });

    test('POST /yolochat/send forwards text to the chat panel', () async {
      Map<String, dynamic>? actionBody;
      final response = await handleYoloChat(
        'POST',
        ['send'],
        _postRequest(
          '/api/yolochat/send',
          body: {'text': 'hello', 'provider': 'echo'},
        ),
        mockBoardCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          expect(board.id, 'b1');
          expect(panel.id, 'p1');
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, isNotNull);
      expect(actionBody!['action'], 'send');
      expect(actionBody!['text'], 'hello');
      expect(actionBody!['provider'], 'echo');
    });

    test('POST /yolochat/send rejects missing text', () async {
      var panelActionCalled = false;
      final response = await handleYoloChat(
        'POST',
        ['send'],
        _postRequest('/api/yolochat/send', body: {'provider': 'echo'}),
        mockBoardCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: () {},
        panelAction: (_, _, _, _) async {
          panelActionCalled = true;
          return _json({});
        },
      );

      expect(response.statusCode, 400);
      expect(panelActionCalled, false);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'Missing "text" field');
    });

    test('unknown route returns notFound', () async {
      var called = false;
      final response = await handleYoloChat(
        'GET',
        ['unknown'],
        _getRequest('/api/yolochat/unknown'),
        mockBoardCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: (msg) {
          called = true;
          return _notFound(msg);
        },
        scheduleRebuild: () {},
        panelAction: (_, _, _, _) async => _json({}),
      );

      expect(response.statusCode, 404);
      expect(called, true);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], 'Unknown yolochat route');
    });
  });
}
