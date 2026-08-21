import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/yolo_chat_handler.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_history.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/board/model/terminal_panel_models.dart';
import 'package:yoloit/features/board/terminal/board_terminal_session_manager.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

/// Minimal in-memory provider so ChatSession construction and stopStreaming
/// never touch real CLI processes.
class _FakeChatProvider extends ChatProvider {
  @override
  String get providerId => 'echo';

  @override
  String get displayName => 'Echo';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) => const Stream.empty();

  @override
  Future<void> stop(String sessionName) async {}

  @override
  bool isRunning(String sessionName) => false;

  @override
  void dispose() {}
}

class _TempPlatformDirs extends PlatformDirs {
  _TempPlatformDirs(this._tmpDir);
  final String _tmpDir;

  @override
  String get configDir => _tmpDir;

  @override
  String get dataDir => _tmpDir;

  @override
  String? get userHome => null;

  @override
  String get logsDir => _tmpDir;

  @override
  String get tempDir => _tmpDir;

  @override
  String get skillsDir => '$_tmpDir/skills';

  @override
  String get yoloitTempDir => '$_tmpDir/tmp';
}

shelf.Request _getRequest(String path, {Map<String, String>? query}) {
  final uri = Uri.parse(
    'http://localhost:8080$path',
  ).replace(queryParameters: query);
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

Future<shelf.Response> _dispatch(
  String method,
  String route,
  shelf.Request request,
  BoardCubit cubit, {
  void Function()? scheduleRebuild,
  Future<shelf.Response> Function(
    BoardCubit cubit,
    BoardDocument board,
    BoardPanelInstance panel,
    Map<String, dynamic> body,
  )?
  panelAction,
}) {
  return handleYoloChat(
    method,
    [route],
    request,
    cubit,
    body: _body,
    json: _json,
    error: _error,
    notFound: _notFound,
    scheduleRebuild: scheduleRebuild ?? () {},
    panelAction: panelAction ?? (_, _, _, _) async => _json({'ok': true}),
  );
}

ChatSession _makeSession(
  String panelId, {
  bool processing = false,
  List<ChatMessage> messages = const [],
}) {
  final session = ChatSession(
    panelId: panelId,
    config: const ChatSessionConfig(
      sessionName: 'test-session',
      workingDir: '/tmp',
      provider: 'echo',
      model: 'echo-model',
    ),
    providerFactory: (_) => _FakeChatProvider(),
  );
  if (processing || messages.isNotEmpty) {
    session.syncFromWidget(messages: messages, isProcessing: processing);
  }
  return session;
}

Future<Map<String, dynamic>> _readJson(shelf.Response response) async =>
    jsonDecode(await response.readAsString()) as Map<String, dynamic>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockBoardCubit mockBoardCubit;
  late BoardDocument testBoard;
  late Directory tmpDir;

  setUpAll(() {
    registerFallbackValue((BoardPanelInstance panel) => panel);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmpDir = Directory.systemTemp.createTempSync('yolo_chat_handler_test_');
    PlatformDirs.setInstance(_TempPlatformDirs(tmpDir.path));
    ChatSessionManager.instance.sessions.clear();
    BoardTerminalSessionManager.instance.clearSessionsForTesting();

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

  tearDown(() {
    for (final session in ChatSessionManager.instance.sessions.values) {
      session.dispose();
    }
    ChatSessionManager.instance.sessions.clear();
    BoardTerminalSessionManager.instance.clearSessionsForTesting();
    PlatformDirs.setInstance(const MacosPlatformDirs());
    tmpDir.deleteSync(recursive: true);
  });

  group('handleYoloChat', () {
    test('GET /yolochat/panels lists chat panels', () async {
      final response = await _dispatch(
        'GET',
        'panels',
        _getRequest('/api/yolochat/panels'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
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
      final response = await _dispatch(
        'POST',
        'send',
        _postRequest(
          '/api/yolochat/send',
          body: {'text': 'hello', 'provider': 'echo'},
        ),
        mockBoardCubit,
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
      final response = await _dispatch(
        'POST',
        'send',
        _postRequest('/api/yolochat/send', body: {'provider': 'echo'}),
        mockBoardCubit,
        panelAction: (_, _, _, _) async {
          panelActionCalled = true;
          return _json({});
        },
      );

      expect(response.statusCode, 400);
      expect(panelActionCalled, false);
      final body = await _readJson(response);
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
      final body = await _readJson(response);
      expect(body['error'], 'Unknown yolochat route');
    });
  });

  group('messages route', () {
    test('GET /yolochat/messages forwards action with parsed limit', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'GET',
        'messages',
        _getRequest(
          '/api/yolochat/messages',
          query: {'board': 'b1', 'panel': 'p1', 'limit': '5'},
        ),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          expect(board.id, 'b1');
          expect(panel.id, 'p1');
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'messages', 'limit': 5});
    });

    test('GET /yolochat/messages omits invalid limit', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'GET',
        'messages',
        _getRequest('/api/yolochat/messages', query: {'limit': 'abc'}),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'messages'});
    });

    test('GET /yolochat/messages errors when chat panel not found', () async {
      final response = await _dispatch(
        'GET',
        'messages',
        _getRequest('/api/yolochat/messages', query: {'panel': 'nope'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'No board.chat panel found (or target not found)');
    });
  });

  group('clear route', () {
    test('POST /yolochat/clear forwards clear action', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'POST',
        'clear',
        _postRequest('/api/yolochat/clear', body: {}),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          expect(board.id, 'b1');
          expect(panel.id, 'p1');
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'clear'});
    });

    test('POST /yolochat/clear errors when chat panel not found', () async {
      final response = await _dispatch(
        'POST',
        'clear',
        _postRequest('/api/yolochat/clear', body: {'panel': 'nope'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'No board.chat panel found (or target not found)');
    });
  });

  group('sessions route', () {
    test('GET /yolochat/sessions returns empty list without sessions', () async {
      final response = await _dispatch(
        'GET',
        'sessions',
        _getRequest('/api/yolochat/sessions'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(body['sessions'], isEmpty);
    });

    test('GET /yolochat/sessions lists active sessions', () async {
      ChatSessionManager.instance.sessions['p1'] = _makeSession('p1');

      final response = await _dispatch(
        'GET',
        'sessions',
        _getRequest('/api/yolochat/sessions'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(
        body['sessions'],
        const [
          {
            'panelId': 'p1',
            'provider': 'echo',
            'model': 'echo-model',
            'messageCount': 0,
            'isProcessing': false,
          },
        ],
      );
    });
  });

  group('history route', () {
    test('GET /yolochat/history returns empty list without saved sessions', () async {
      final response = await _dispatch(
        'GET',
        'history',
        _getRequest('/api/yolochat/history'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(body['sessions'], isEmpty);
    });

    test('GET /yolochat/history lists saved sessions', () async {
      await ChatSessionHistory.instance.upsert(
        ChatSessionEntry(
          id: 's1',
          sessionName: 'Saved',
          provider: 'copilot',
          model: 'gpt-5',
          workingDir: '/work',
          createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
          lastMessageAt: DateTime.utc(2024, 1, 3),
          messageCount: 2,
        ),
      );

      final response = await _dispatch(
        'GET',
        'history',
        _getRequest('/api/yolochat/history'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(
        body['sessions'],
        const [
          {
            'id': 's1',
            'sessionName': 'Saved',
            'provider': 'copilot',
            'model': 'gpt-5',
            'workingDir': '/work',
            'messageCount': 2,
            'createdAt': '2024-01-02T03:04:05.000Z',
            'lastMessageAt': '2024-01-03T00:00:00.000Z',
          },
        ],
      );
    });
  });

  group('restore route', () {
    test('POST /yolochat/restore rejects missing sessionId', () async {
      final response = await _dispatch(
        'POST',
        'restore',
        _postRequest('/api/yolochat/restore', body: {}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'Missing "sessionId" field');
    });

    test('POST /yolochat/restore errors on unknown session', () async {
      final response = await _dispatch(
        'POST',
        'restore',
        _postRequest('/api/yolochat/restore', body: {'sessionId': 'nope'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'Saved session not found: nope');
    });

    test('POST /yolochat/restore restores a saved session into the panel', () async {
      await ChatSessionHistory.instance.upsert(
        ChatSessionEntry(
          id: 's1',
          sessionName: 'Saved Session',
          provider: 'copilot',
          model: 'gpt-5',
          workingDir: '/work',
          createdAt: DateTime.utc(2024, 1, 2),
          messageCount: 1,
        ),
        messages: [
          {'role': 'user', 'content': 'hi'},
        ],
      );

      BoardPanelInstance? updated;
      var rebuildScheduled = false;
      when(
        () => mockBoardCubit.updatePanel(
          any(),
          any(),
          boardId: any(named: 'boardId'),
        ),
      ).thenAnswer((invocation) async {
        final update =
            invocation.positionalArguments[1]
                as BoardPanelInstance Function(BoardPanelInstance);
        updated = update(testBoard.panels.first);
      });

      final response = await _dispatch(
        'POST',
        'restore',
        _postRequest(
          '/api/yolochat/restore',
          body: {'sessionId': 's1', 'board': 'b1', 'panel': 'p1'},
        ),
        mockBoardCubit,
        scheduleRebuild: () => rebuildScheduled = true,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      final restored = body['restored'] as Map<String, dynamic>;
      expect(restored['id'], 's1');
      expect(restored['sessionName'], 'Saved Session');
      expect(restored['messageCount'], 1);
      expect(rebuildScheduled, true);
      expect(updated, isNotNull);
      expect(updated!.state['provider'], 'copilot');
      expect(updated!.state['model'], 'gpt-5');
      expect(updated!.state['sessionName'], 'Saved Session');
      expect(updated!.state['workingDir'], '/work');
      expect((updated!.state['messages'] as List).length, 1);
    });
  });

  group('status route', () {
    test('GET /yolochat/status forwards status action', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'GET',
        'status',
        _getRequest('/api/yolochat/status'),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          expect(board.id, 'b1');
          expect(panel.id, 'p1');
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'status'});
    });

    test('GET /yolochat/status errors without any board', () async {
      when(
        () => mockBoardCubit.state,
      ).thenReturn(const BoardState(isLoaded: true));

      final response = await _dispatch(
        'GET',
        'status',
        _getRequest('/api/yolochat/status'),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'No board.chat panel found (or target not found)');
    });
  });

  group('stop route', () {
    test('POST /yolochat/stop forwards stop action for explicit target', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'POST',
        'stop',
        _postRequest('/api/yolochat/stop', body: {'board': 'b1', 'panel': 'p1'}),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'stop'});
    });

    test('POST /yolochat/stop errors when explicit target not found', () async {
      final response = await _dispatch(
        'POST',
        'stop',
        _postRequest('/api/yolochat/stop', body: {'panel': 'nope'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'No board.chat panel found (or target not found)');
    });

    test('POST /yolochat/stop stops all active streams without a target', () async {
      final session = _makeSession('p1', processing: true);
      ChatSessionManager.instance.sessions['p1'] = session;

      var panelActionCalled = false;
      final response = await _dispatch(
        'POST',
        'stop',
        _postRequest('/api/yolochat/stop', body: {}),
        mockBoardCubit,
        panelAction: (_, _, _, _) async {
          panelActionCalled = true;
          return _json({});
        },
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(body['stopped'], 1);
      expect(body['message'], 'Stopped 1 active chat stream(s)');
      expect(panelActionCalled, false);
      expect(session.isProcessing, false);
    });

    test('POST /yolochat/stop falls back to panel stop without active streams', () async {
      Map<String, dynamic>? actionBody;
      final response = await _dispatch(
        'POST',
        'stop',
        _postRequest('/api/yolochat/stop', body: {}),
        mockBoardCubit,
        panelAction: (cubit, board, panel, body) async {
          actionBody = body;
          return _json({'ok': true});
        },
      );

      expect(response.statusCode, 200);
      expect(actionBody, {'action': 'stop'});
    });
  });

  group('logs route', () {
    test('GET /yolochat/logs renders placeholder without a session', () async {
      final response = await _dispatch(
        'GET',
        'logs',
        _getRequest('/api/yolochat/logs'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      expect(response.headers['content-type'], contains('text/plain'));
      final text = await response.readAsString();
      expect(text, contains('=== YoLoIT Chat Logs ==='));
      expect(text, contains('Board: Test Board'));
      expect(text, contains('Panel: Chat'));
      expect(text, contains('Provider: unknown'));
      expect(text, contains('Model: unknown'));
      expect(text, contains('Messages: 0'));
    });

    test('GET /yolochat/logs renders session messages with tool calls', () async {
      ChatSessionManager.instance.sessions['p1'] = _makeSession(
        'p1',
        messages: [
          ChatMessage(
            id: 'm1',
            role: ChatRole.user,
            content: 'hello',
            timestamp: DateTime.utc(2024),
          ),
          ChatMessage(
            id: 'm2',
            role: ChatRole.assistant,
            content: 'working on it',
            timestamp: DateTime.utc(2024),
            toolCalls: const [
              ChatToolCall(
                toolCallId: 'tc1',
                toolName: 'read_file',
                arguments: {'path': '/x'},
                result: 'file-ok',
              ),
            ],
          ),
        ],
      );

      final response = await _dispatch(
        'GET',
        'logs',
        _getRequest('/api/yolochat/logs'),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final text = await response.readAsString();
      expect(text, contains('Provider: echo'));
      expect(text, contains('Model: echo-model'));
      expect(text, contains('Messages: 2'));
      expect(text, contains('--- [user] ---'));
      expect(text, contains('hello'));
      expect(text, contains('--- [assistant] ---'));
      expect(text, contains('[tool] read_file({path: /x})'));
      expect(text, contains('[result] file-ok'));
    });

    test('GET /yolochat/logs errors when chat panel not found', () async {
      final response = await _dispatch(
        'GET',
        'logs',
        _getRequest('/api/yolochat/logs', query: {'panel': 'nope'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'No board.chat panel found (or target not found)');
    });
  });

  group('terminal-input route', () {
    test('POST /yolochat/terminal-input rejects missing text', () async {
      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest('/api/yolochat/terminal-input', body: {}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'Missing "text" field');
    });

    test('POST /yolochat/terminal-input writes to an explicit session', () async {
      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest(
          '/api/yolochat/terminal-input',
          body: {'text': 'ls', 'sessionId': 'ext-1'},
        ),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(body['sessionId'], 'ext-1');
      expect(body['bytes'], 3);
      expect(body['appendNewline'], true);
      expect(body.containsKey('target'), false);
    });

    test('POST /yolochat/terminal-input honors appendNewline=false', () async {
      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest(
          '/api/yolochat/terminal-input',
          body: {'text': 'abc', 'sessionId': 'ext-2', 'appendNewline': false},
        ),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['bytes'], 3);
      expect(body['appendNewline'], false);
    });

    test('POST /yolochat/terminal alias accepts input/session keys and enter=false', () async {
      final response = await _dispatch(
        'POST',
        'terminal',
        _postRequest(
          '/api/yolochat/terminal',
          body: {'input': 'x', 'session': 'ext-3', 'enter': false},
        ),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['sessionId'], 'ext-3');
      expect(body['bytes'], 1);
      expect(body['appendNewline'], false);
    });

    test('POST /yolochat/terminal-input errors without a terminal panel', () async {
      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest('/api/yolochat/terminal-input', body: {'text': 'ls'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(
        body['error'],
        'No board.terminal panel found (or target not found)',
      );
    });

    test('POST /yolochat/terminal-input errors when panel is not configured', () async {
      const terminalBoard = BoardDocument(
        id: 'b1',
        name: 'Test Board',
        panels: [
          BoardPanelInstance(
            id: 't1',
            type: 'board.terminal',
            title: 'Term',
            bounds: BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
          ),
        ],
      );
      when(() => mockBoardCubit.state).thenReturn(
        const BoardState(
          boards: [terminalBoard],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );

      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest('/api/yolochat/terminal-input', body: {'text': 'ls'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 400);
      final body = await _readJson(response);
      expect(body['error'], 'Target terminal panel is not configured');
    });

    test('POST /yolochat/terminal-input writes to a configured terminal panel', () async {
      final terminalBoard = BoardDocument(
        id: 'b1',
        name: 'Test Board',
        panels: [
          BoardPanelInstance(
            id: 't1',
            type: 'board.terminal',
            title: 'Term',
            bounds: const BoardPanelBounds(x: 0, y: 0, width: 400, height: 300),
            state: {
              'config': const BoardTerminalConfig(
                sessionId: 'term-1',
                sessionName: 'Term',
                workingDir: '/tmp',
              ).toJson(),
            },
          ),
        ],
      );
      when(() => mockBoardCubit.state).thenReturn(
        BoardState(boards: [terminalBoard], activeBoardId: 'b1', isLoaded: true),
      );
      BoardTerminalSessionManager.instance.setSessionForTesting(
        'term-1',
        AgentSession(
          id: 'term-1',
          type: AgentType.terminal,
          workspacePath: '/tmp',
        ),
      );

      final response = await _dispatch(
        'POST',
        'terminal-input',
        _postRequest('/api/yolochat/terminal-input', body: {'text': 'pwd'}),
        mockBoardCubit,
      );

      expect(response.statusCode, 200);
      final body = await _readJson(response);
      expect(body['ok'], true);
      expect(body['sessionId'], 'term-1');
      expect(body['bytes'], 4);
      expect(body['appendNewline'], true);
      final target = body['target'] as Map<String, dynamic>;
      expect(target['boardId'], 'b1');
      expect(target['boardName'], 'Test Board');
      expect(target['panelId'], 't1');
      expect(target['panelTitle'], 'Term');
    });
  });
}
