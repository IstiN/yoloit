import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/agents_handler.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/agent_config_service.dart';
import 'package:yoloit/features/terminal/bloc/terminal_cubit.dart';
import 'package:yoloit/features/terminal/bloc/terminal_state.dart';
import 'package:yoloit/features/terminal/models/agent_session.dart';
import 'package:yoloit/features/terminal/models/agent_type.dart';

class _MockBoardCubit extends Mock implements BoardCubit {}

class _MockTerminalCubit extends Mock implements TerminalCubit {}

class _MockAgentConfigService extends Mock implements AgentConfigService {}

class _MockChatSessionManager extends Mock implements ChatSessionManager {}

class _MockChatSession extends Mock implements ChatSession {}

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

BoardPanelBounds _nextAvailableBounds(
  BoardDocument board, {
  required double preferredWidth,
  required double preferredHeight,
}) =>
    const BoardPanelBounds(x: 0, y: 0, width: 420, height: 500);

void _scheduleRebuild() {}

AgentConfig _agentConfig({String id = 'copilot'}) => AgentConfig(
  id: id,
  displayName: id,
  iconLabel: id[0].toUpperCase(),
  launchCommand: id,
  visible: true,
  isBuiltIn: true,
);

void main() {
  setUpAll(() {
    registerFallbackValue(
      BoardPanelInstance(
        id: '',
        type: '',
        title: '',
        bounds: const BoardPanelBounds(x: 0, y: 0, width: 0, height: 0),
      ),
    );
    registerFallbackValue(
      const ChatSessionConfig(sessionName: '', workingDir: '', provider: ''),
    );
  });
  group('handleAgents', () {
    late _MockBoardCubit mockBoardCubit;
    late _MockTerminalCubit mockTerminalCubit;
    late _MockAgentConfigService mockAgentConfigService;
    late _MockChatSessionManager mockChatSessionManager;

    setUp(() {
      mockBoardCubit = _MockBoardCubit();
      mockTerminalCubit = _MockTerminalCubit();
      mockAgentConfigService = _MockAgentConfigService();
      mockChatSessionManager = _MockChatSessionManager();

      when(() => mockTerminalCubit.state).thenReturn(
        TerminalLoaded(
          sessions: [],
          activeIndex: 0,
          allSessions: [
            AgentSession(
              id: 's1',
              type: AgentType.copilot,
              workspacePath: '/tmp',
              status: AgentStatus.live,
            ),
          ],
        ),
      );

      when(() => mockAgentConfigService.load()).thenAnswer(
        (_) async => [_agentConfig(id: 'copilot')],
      );
      when(() => mockAgentConfigService.defaultAgentId).thenReturn('copilot');
      when(() => mockAgentConfigService.defaultAgentType).thenReturn(AgentType.copilot);
      when(() => mockAgentConfigService.setDefaultAgentId(any())).thenAnswer((_) async {});
      when(() => mockAgentConfigService.save(any())).thenAnswer((_) async {});

      when(() => mockBoardCubit.state).thenReturn(
        BoardState(
          boards: [
            BoardDocument(
              id: 'b1',
              name: 'Board 1',
              panels: [],
            ),
          ],
          activeBoardId: 'b1',
          isLoaded: true,
        ),
      );
      when(() => mockBoardCubit.addPanel(any(), boardId: any(named: 'boardId'))).thenAnswer((_) async {});
      when(() => mockBoardCubit.setActiveBoard(any())).thenAnswer((_) async {});
      when(() => mockBoardCubit.focusPanel(any(), boardId: any(named: 'boardId'))).thenAnswer((_) async {});
    });

    test('GET /agents/list returns agents and sessions', () async {
      final response = await handleAgents(
        'GET',
        [],
        _getRequest('/api/agents'),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['defaultAgentId'], 'copilot');
      expect((body['agents'] as List).length, 1);
      expect((body['sessions'] as List).length, 1);
    });

    test('POST /agents/default sets default agent', () async {
      final response = await handleAgents(
        'POST',
        ['default'],
        _postRequest('/api/agents/default', body: {'id': 'claude'}),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['defaultAgentId'], 'claude');
    });

    test('POST /agents/default with invalid id returns error', () async {
      final response = await handleAgents(
        'POST',
        ['default'],
        _postRequest('/api/agents/default', body: {'id': 'invalid_agent_12345'}),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
    });

    test('POST /agents/run without board cubit returns error', () async {
      final response = await handleAgents(
        'POST',
        ['run'],
        _postRequest('/api/agents/run'),
        cubit: null,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], contains('Board cubit'));
    });

    test('POST /agents/run creates panel and sends task', () async {
      final mockSession = _MockChatSession();
      when(() => mockChatSessionManager.getOrCreate(any(), any())).thenReturn(mockSession);
      when(() => mockSession.sendMessage(text: any(named: 'text'))).thenReturn(true);

      final response = await handleAgents(
        'POST',
        ['run'],
        _postRequest('/api/agents/run', body: {'task': 'Do something'}),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['taskSent'], true);
      expect(body['panel'], isA<Map<String, dynamic>>());
    });

    test('POST /agents/run without task creates panel only', () async {
      final response = await handleAgents(
        'POST',
        ['run'],
        _postRequest('/api/agents/run'),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['taskSent'], false);
    });

    test('POST /agents/config updates config', () async {
      final response = await handleAgents(
        'POST',
        ['config'],
        _postRequest('/api/agents/config', body: {
          'id': 'copilot',
          'defaultModel': 'gpt-5',
          'asrMode': 'local',
        }),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['agent']['defaultModel'], 'gpt-5');
      expect(body['agent']['asrMode'], 'local');
    });

    test('POST /agents/config missing id returns error', () async {
      final response = await handleAgents(
        'POST',
        ['config'],
        _postRequest('/api/agents/config'),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
    });

    test('POST /agents/config unknown id returns error', () async {
      when(() => mockAgentConfigService.load()).thenAnswer(
        (_) async => [],
      );

      final response = await handleAgents(
        'POST',
        ['config'],
        _postRequest('/api/agents/config', body: {'id': 'unknown'}),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
    });

    test('POST /agents/config invalid asrMode returns error', () async {
      final response = await handleAgents(
        'POST',
        ['config'],
        _postRequest('/api/agents/config', body: {
          'id': 'copilot',
          'asrMode': 'invalid',
        }),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], contains('asrMode'));
    });

    test('terminal cubit not available returns error', () async {
      final response = await handleAgents(
        'GET',
        [],
        _getRequest('/api/agents'),
        cubit: mockBoardCubit,
        terminalCubit: null,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['error'], contains('Terminal cubit'));
    });

    test('unknown route returns notFound', () async {
      final response = await handleAgents(
        'GET',
        ['unknown'],
        _getRequest('/api/agents/unknown'),
        cubit: mockBoardCubit,
        terminalCubit: mockTerminalCubit,
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        scheduleRebuild: _scheduleRebuild,
        nextAvailableBoundsFor: _nextAvailableBounds,
        agentConfigService: mockAgentConfigService,
        chatSessionManager: mockChatSessionManager,
      );

      expect(response.statusCode, 404);
    });
  });
}
