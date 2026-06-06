import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/search_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

class _MockChatSessionManager extends Mock implements ChatSessionManager {}

class _MockChatSessionHistory extends Mock implements ChatSessionHistory {}

class _MockChatSession extends Mock implements ChatSession {}

shelf.Request _getRequest(String path, {Map<String, String>? query}) {
  final uri = Uri.parse('http://localhost:8080$path').replace(queryParameters: query);
  return shelf.Request('GET', uri);
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

BoardDocument _board({
  String id = 'b1',
  String name = 'Test Board',
  List<BoardPanelInstance> panels = const [],
}) => BoardDocument(id: id, name: name, panels: panels);

BoardPanelInstance _panel({
  String id = 'p1',
  String type = 'board.chat',
  String title = 'Chat',
  Map<String, dynamic> state = const {},
}) => BoardPanelInstance(
  id: id,
  type: type,
  title: title,
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
  state: state,
);

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });
  group('handleSearch', () {
    late _MockBoardCubit mockBoardCubit;

    setUp(() {
      mockBoardCubit = _MockBoardCubit();
      when(() => mockBoardCubit.state).thenReturn(
        BoardState(
          boards: [
            _board(
              panels: [
                _panel(id: 'chat1', title: 'Assistant'),
              ],
            ),
          ],
          isLoaded: true,
        ),
      );
    });

    test('missing query returns error', () async {
      final response = await handleSearch(
        'GET',
        [],
        _getRequest('/api/search'),
        mockBoardCubit,
        json: _json,
        error: _error,
        notFound: _notFound,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('search boards scope', () async {
      final response = await handleSearch(
        'GET',
        [],
        _getRequest('/api/search', query: {'q': 'Test'}),
        mockBoardCubit,
        json: _json,
        error: _error,
        notFound: _notFound,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['query'], 'Test');
      final items = body['items'] as List;
      expect(items.any((i) => i['scope'] == 'board'), true);
    });

    test('unknown route returns notFound', () async {
      final response = await handleSearch(
        'POST',
        [],
        _getRequest('/api/search', query: {'q': 'hello'}),
        mockBoardCubit,
        json: _json,
        error: _error,
        notFound: _notFound,
      );

      expect(response.statusCode, 404);
    });

    test('search active chats', () async {
      final mockManager = _MockChatSessionManager();
      final mockSession = _MockChatSession();
      when(() => mockManager.activeSessionIds).thenReturn(['chat1']);
      when(() => mockManager.get('chat1')).thenReturn(mockSession);
      when(() => mockSession.messages).thenReturn([
        ChatMessage(
          id: 'm1',
          role: ChatRole.user,
          content: 'hello world',
        ),
      ]);
      when(() => mockSession.config).thenReturn(
        const ChatSessionConfig(
          sessionName: 'test',
          workingDir: '/tmp',
          provider: 'copilot',
        ),
      );

      final response = await handleSearch(
        'GET',
        [],
        _getRequest('/api/search', query: {'q': 'hello', 'scope': 'active-chats'}),
        mockBoardCubit,
        json: _json,
        error: _error,
        notFound: _notFound,
        chatSessionManager: mockManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final items = body['items'] as List;
      expect(items.any((i) => i['scope'] == 'active-chat'), true);
    });

    test('search saved sessions', () async {
      final mockHistory = _MockChatSessionHistory();
      when(() => mockHistory.loadAll()).thenAnswer(
        (_) async => [
          ChatSessionEntry(
            id: 's1',
            sessionName: 'Saved',
            provider: 'copilot',
            model: 'gpt-4',
            workingDir: '/tmp',
            createdAt: DateTime(2024, 1, 1),
          ),
        ],
      );
      when(() => mockHistory.loadMessages('s1')).thenAnswer(
        (_) async => [
          {'role': 'user', 'content': 'saved message'},
        ],
      );

      final response = await handleSearch(
        'GET',
        [],
        _getRequest('/api/search', query: {'q': 'saved', 'scope': 'history'}),
        mockBoardCubit,
        json: _json,
        error: _error,
        notFound: _notFound,
        chatSessionHistory: mockHistory,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final items = body['items'] as List;
      expect(items.any((i) => i['scope'] == 'saved-session'), true);
    });
  });

  group('searchBoards', () {
    test('matches board name', () {
      final cubit = _MockBoardCubit();
      when(() => cubit.state).thenReturn(
        BoardState(
          boards: [_board(name: 'Project Alpha')],
          isLoaded: true,
        ),
      );

      final results = searchBoards(cubit, 'Alpha');
      expect(results.length, 1);
      expect(results.first['boardName'], 'Project Alpha');
      expect(results.first['panelId'], null);
    });

    test('matches panel title', () {
      final cubit = _MockBoardCubit();
      when(() => cubit.state).thenReturn(
        BoardState(
          boards: [
            _board(
              panels: [_panel(id: 'p1', title: 'My Chat')],
            ),
          ],
          isLoaded: true,
        ),
      );

      final results = searchBoards(cubit, 'Chat');
      expect(results.any((r) => r['panelTitle'] == 'My Chat'), true);
    });

    test('matches panel id', () {
      final cubit = _MockBoardCubit();
      when(() => cubit.state).thenReturn(
        BoardState(
          boards: [
            _board(
              panels: [_panel(id: 'demo_copilot', title: '')],
            ),
          ],
          isLoaded: true,
        ),
      );

      final results = searchBoards(cubit, 'demo_copilot');
      expect(results.any((r) => r['panelId'] == 'demo_copilot'), true);
    });

    test('no match returns empty', () {
      final cubit = _MockBoardCubit();
      when(() => cubit.state).thenReturn(
        BoardState(
          boards: [_board(name: 'Board')],
          isLoaded: true,
        ),
      );

      final results = searchBoards(cubit, 'xyz');
      expect(results, isEmpty);
    });
  });

  group('matchSnippet', () {
    test('exact substring match', () {
      final result = matchSnippet('hello world', 'world');
      expect(result, isNotNull);
      expect(result, contains('world'));
    });

    test('separator-normalised match', () {
      final result = matchSnippet('demo_copilot', 'demo copilot');
      expect(result, isNotNull);
    });

    test('all words match', () {
      final result = matchSnippet('the quick brown fox', 'fox quick');
      expect(result, isNotNull);
    });

    test('no match returns null', () {
      final result = matchSnippet('hello world', 'xyz');
      expect(result, isNull);
    });
  });

  group('collectSearchStrings', () {
    test('extracts strings from nested map', () {
      final result = collectSearchStrings({
        'title': 'Note',
        'items': [
          {'text': 'item1'},
          {'text': 'item2'},
        ],
      });
      expect(result, contains('Note'));
      expect(result, contains('item1'));
      expect(result, contains('item2'));
    });

    test('ignores id and timestamp keys', () {
      final result = collectSearchStrings({
        'id': 'should-be-skipped',
        'timestamp': 'also-skipped',
        'text': 'included',
      });
      expect(result, isNot(contains('should-be-skipped')));
      expect(result, isNot(contains('also-skipped')));
      expect(result, contains('included'));
    });

    test('handles depth limit', () {
      final result = collectSearchStrings({
        'a': {
          'b': {
            'c': {
              'd': {
                'e': 'deep',
              },
            },
          },
        },
      });
      expect(result, isEmpty);
    });
  });
}
