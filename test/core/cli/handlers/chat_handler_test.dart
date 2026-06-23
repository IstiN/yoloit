// covers-write: board.chat
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/cli/handlers/chat_handler.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class _FakeChatProvider extends ChatProvider {
  final Map<String, String> _sessionIds = {};
  final List<bool> sentIsFirstMessages = [];

  @override
  String get providerId => 'copilot';

  @override
  String get displayName => 'Fake';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool isRunning(String sessionName) => false;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    sentIsFirstMessages.add(isFirstMessage);
    return const Stream<ChatEvent>.empty();
  }

  @override
  Future<void> stop(String sessionName) async {}

  @override
  void dispose() {}

  @override
  void detach() {}

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _sessionIds[sessionName];
}

BoardPanelInstance _panel({
  String id = 'p1',
  Map<String, dynamic> state = const {},
}) => BoardPanelInstance(
  id: id,
  type: 'board.chat',
  title: 'Chat',
  bounds: const BoardPanelBounds(x: 0, y: 0, width: 300, height: 200),
  state: state,
);

void main() {
  late _FakeChatProvider provider;
  late ChatSessionManager sessionManager;
  late ChatCliHandler handler;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    provider = _FakeChatProvider();
    sessionManager = ChatSessionManager.testInstance(
      providerFactory: (_) => provider,
    );
    handler = ChatCliHandler(sessionManager: sessionManager);
  });

  tearDown(() {
    sessionManager.disposeAll();
  });

  test('typeId matches', () {
    expect(handler.typeId, 'board.chat');
  });

  test('supportedActions includes new actions', () {
    expect(
      handler.supportedActions,
      containsAll([
        'send',
        'messages',
        'config',
        'clear',
        'status',
        'stop',
        'sessions',
      ]),
    );
  });

  test('messages action returns messages from panel state', () async {
    final panel = _panel(
      state: {
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    final r = await handler.handleAction('messages', {}, panel);
    expect(r.ok, isTrue);
    expect((r.data!['messages'] as List).length, 1);
  });

  test('messages action prefers live session data', () async {
    final panel = _panel(
      state: {
        'config': {
          'sessionName': 'test',
          'workingDir': '/tmp',
          'provider': 'copilot',
        },
        'messages': [
          {'role': 'user', 'content': 'old'},
        ],
      },
    );
    // Create a session with more messages
    final session = sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(sessionName: 'test', workingDir: '/tmp'),
    );
    session.restoreMessages([
      {'id': 'm1', 'role': 'user', 'content': 'msg1'},
      {'id': 'm2', 'role': 'assistant', 'content': 'reply1'},
    ]);
    final r = await handler.handleAction('messages', {}, panel);
    expect(r.ok, isTrue);
    expect((r.data!['total'] as int), 2);
  });

  test('send requires message', () async {
    final r = await handler.handleAction('send', {}, _panel());
    expect(r.ok, isFalse);
  });

  test('config returns provider info from panel state', () async {
    final panel = _panel(
      state: {
        'config': {'provider': 'openai', 'model': 'gpt-4'},
      },
    );
    final r = await handler.handleAction('config', {}, panel);
    expect(r.ok, isTrue);
    expect(r.data!['config']['provider'], 'openai');
  });

  test('config update propagates to live session', () async {
    final panel = _panel(
      state: {
        'config': {
          'sessionName': 'test',
          'workingDir': '/tmp',
          'provider': 'copilot',
          'model': 'gpt-5-mini',
        },
      },
    );
    // Create a session first
    sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(sessionName: 'test', workingDir: '/tmp'),
    );
    final r = await handler.handleAction('config', {
      'model': 'claude-opus',
    }, panel);
    expect(r.ok, isTrue);
    expect(r.data!['config']['model'], 'claude-opus');
    final session = sessionManager.get('p1');
    expect(session?.config.model, 'claude-opus');
  });

  test('config update normalizes cloud provider id format', () async {
    final panel = _panel(
      state: {
        'config': {
          'sessionName': 'test',
          'workingDir': '/tmp',
          'provider': 'copilot',
        },
      },
    );
    final r = await handler.handleAction('config', {
      'provider': 'cloud-123',
    }, panel);
    expect(r.ok, isTrue);
    expect(r.data!['config']['provider'], 'cloud:cloud-123');
  });

  test('send restores persisted copilot session id before resuming', () async {
    final panel = _panel(
      state: {
        'config': {
          'sessionName': 'test',
          'workingDir': '/tmp',
          'provider': 'copilot',
          'model': 'gpt-5-mini',
        },
        'messages': [
          {'id': 'm1', 'role': 'user', 'content': 'hello'},
        ],
        'copilotSessionId': 'copilot-session-123',
      },
    );

    final r = await handler.handleAction('send', {'text': 'resume me'}, panel);

    expect(r.ok, isTrue);
    final session = sessionManager.get('p1');
    expect(session, isNotNull);
    expect(session!.copilotSessionId, 'copilot-session-123');
    expect(session.provider.getSessionId('test'), 'copilot-session-123');
    expect(session.isFirstMessage, isFalse);
    expect(provider.sentIsFirstMessages, [false]);
  });

  test(
    'send restores copilot session id from config when top-level state is missing',
    () async {
      final panel = _panel(
        state: {
          'config': {
            'sessionName': 'test',
            'workingDir': '/tmp',
            'provider': 'copilot',
            'model': 'gpt-5-mini',
            'copilotSessionId': 'copilot-session-from-config',
          },
          'messages': [
            {'id': 'm1', 'role': 'user', 'content': 'hello'},
          ],
        },
      );

      final r = await handler.handleAction('send', {
        'text': 'resume me',
      }, panel);

      expect(r.ok, isTrue);
      final session = sessionManager.get('p1');
      expect(session, isNotNull);
      expect(session!.copilotSessionId, 'copilot-session-from-config');
      expect(
        session.provider.getSessionId('test'),
        'copilot-session-from-config',
      );
      expect(provider.sentIsFirstMessages, [false]);
    },
  );

  test('send restores persisted cursor session id before resuming', () async {
    final panel = _panel(
      state: {
        'config': {
          'sessionName': 'test',
          'workingDir': '/tmp',
          'provider': 'cursor',
          'model': 'claude-4-sonnet',
        },
        'messages': [
          {'id': 'm1', 'role': 'user', 'content': 'hello'},
        ],
        'cursorSessionId': 'cursor-session-123',
      },
    );

    final r = await handler.handleAction('send', {'text': 'resume me'}, panel);

    expect(r.ok, isTrue);
    final session = sessionManager.get('p1');
    expect(session, isNotNull);
    expect(session!.cursorSessionId, 'cursor-session-123');
    expect(session.provider.getSessionId('test'), 'cursor-session-123');
    expect(session.isFirstMessage, isFalse);
    expect(provider.sentIsFirstMessages, [false]);
  });

  test(
    'send restores cursor session id from config when top-level state is missing',
    () async {
      final panel = _panel(
        state: {
          'config': {
            'sessionName': 'test',
            'workingDir': '/tmp',
            'provider': 'cursor',
            'model': 'claude-4-sonnet',
            'cursorSessionId': 'cursor-session-from-config',
          },
          'messages': [
            {'id': 'm1', 'role': 'user', 'content': 'hello'},
          ],
        },
      );

      final r = await handler.handleAction('send', {
        'text': 'resume me',
      }, panel);

      expect(r.ok, isTrue);
      final session = sessionManager.get('p1');
      expect(session, isNotNull);
      expect(session!.cursorSessionId, 'cursor-session-from-config');
      expect(
        session.provider.getSessionId('test'),
        'cursor-session-from-config',
      );
      expect(provider.sentIsFirstMessages, [false]);
    },
  );

  test('clear resets messages on live session', () async {
    final panel = _panel(
      state: {
        'messages': [
          {'role': 'user', 'content': 'hi'},
        ],
      },
    );
    // Create a session and add messages
    final session = sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(sessionName: 'test', workingDir: '/tmp'),
    );
    session.restoreMessages([
      {'id': 'm1', 'role': 'user', 'content': 'hi'},
    ]);
    expect(session.messages, isNotEmpty);
    final r = await handler.handleAction('clear', {}, panel);
    expect(r.ok, isTrue);
    expect(session.messages, isEmpty);
  });

  test('status returns hasSession false when no session', () async {
    final r = await handler.handleAction(
      'status',
      {},
      _panel(id: 'no-session'),
    );
    expect(r.ok, isTrue);
    expect(r.data!['hasSession'], false);
  });

  test('status returns session info when session exists', () async {
    sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(
        sessionName: 'test',
        workingDir: '/tmp',
        provider: 'cursor',
        model: 'claude-opus',
      ),
    );
    final r = await handler.handleAction('status', {}, _panel());
    expect(r.ok, isTrue);
    expect(r.data!['hasSession'], true);
    expect(r.data!['provider'], 'cursor');
    expect(r.data!['model'], 'claude-opus');
  });

  test('sessions lists all active sessions', () async {
    sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(sessionName: 's1', workingDir: '/tmp'),
    );
    sessionManager.getOrCreate(
      'p2',
      ChatSessionConfig(
        sessionName: 's2',
        workingDir: '/tmp',
        provider: 'cursor',
      ),
    );
    final r = await handler.handleAction('sessions', {}, _panel());
    expect(r.ok, isTrue);
    final sessions = r.data!['sessions'] as List;
    expect(sessions.length, 2);
  });

  test('stop returns message when no active stream', () async {
    final r = await handler.handleAction('stop', {}, _panel());
    expect(r.ok, isTrue);
    expect(r.message, contains('No active stream'));
  });

  test('getContent prefers live session data', () {
    final session = sessionManager.getOrCreate(
      'p1',
      ChatSessionConfig(sessionName: 'test', workingDir: '/tmp'),
    );
    session.restoreMessages([
      {'id': 'm1', 'role': 'user', 'content': 'live message'},
    ]);
    final content = handler.getContent(_panel());
    expect(content['messageCount'], 1);
    expect(content['isProcessing'], false);
    final messages = content['messages'] as List;
    expect(messages.first['content'], 'live message');
  });

  test('set-follow-up stores draft in panel state', () async {
    final panel = _panel();
    final r = await handler.handleAction(
      'set-follow-up',
      {'text': 'Follow up text'},
      panel,
    );
    expect(r.ok, isTrue);
    expect(r.stateUpdate, containsPair('_followUpDraft', 'Follow up text'));
  });

  test('set-follow-up clear removes draft from panel state', () async {
    final panel = _panel(state: {'_followUpDraft': 'old'});
    final r = await handler.handleAction('set-follow-up', {'clear': true}, panel);
    expect(r.ok, isTrue);
    expect(r.stateUpdate, isNot(contains('_followUpDraft')));
  });
}
