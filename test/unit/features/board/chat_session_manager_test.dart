import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class FakeChatProvider extends ChatProvider {
  FakeChatProvider({this.id = 'fake'});

  final String id;
  final List<String> sentMessages = [];
  final List<List<String>> sentAttachments = [];
  final List<ChatSessionConfig> sentConfigs = [];
  final List<bool> sentIsFirstMessages = [];
  final List<ChatRuntimeContext?> sentRuntimeContexts = [];
  StreamController<ChatEvent>? _controller;
  bool disposed = false;
  bool detached = false;
  bool stopped = false;
  final Map<String, String> _sessionIds = {};

  @override
  String get providerId => id;

  @override
  String get displayName => 'Fake';

  @override
  List<ChatModelInfo> get availableModels => const [
    ChatModelInfo(id: 'fake-model', displayName: 'Fake Model'),
  ];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.filePath;

  @override
  bool isRunning(String sessionName) => _controller != null;

  @override
  Stream<ChatEvent> sendMessage({
    required String message,
    required ChatSessionConfig config,
    required bool isFirstMessage,
    List<String> attachments = const [],
    ChatRuntimeContext? runtimeContext,
    List<Map<String, Object?>>? audioContentOverride,
  }) {
    sentMessages.add(message);
    sentAttachments.add(List<String>.from(attachments));
    sentConfigs.add(config);
    sentIsFirstMessages.add(isFirstMessage);
    sentRuntimeContexts.add(runtimeContext);
    _controller = StreamController<ChatEvent>();
    return _controller!.stream;
  }

  void emitEvent(ChatEvent event) {
    _controller?.add(event);
  }

  void emitError(Object error) {
    _controller?.addError(error);
  }

  Future<void> complete() async {
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  @override
  Future<void> stop(String sessionName) async {
    stopped = true;
    await complete();
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(complete());
  }

  @override
  void detach() {
    detached = true;
  }

  @override
  void setSessionId(String sessionName, String sessionId) {
    _sessionIds[sessionName] = sessionId;
  }

  @override
  String? getSessionId(String sessionName) => _sessionIds[sessionName];
}

const _workingDir =
    '/Users/Uladzimir_Klyshevich/.config/yoloit/workspaces/yoloit_1775836124022/yoloit';

ChatSessionConfig _config({String provider = 'copilot'}) => ChatSessionConfig(
  sessionName: 'test-session',
  workingDir: _workingDir,
  provider: provider,
);

ChatEvent _assistantDelta(String text) => ChatEvent(
  type: ChatEventType.assistantDelta,
  rawType: 'assistant.message_delta',
  data: {'deltaContent': text},
);

ChatEvent _assistantMessage(
  String content, {
  String messageId = 'msg-1',
  int? outputTokens,
}) => ChatEvent(
  type: ChatEventType.assistantMessage,
  rawType: 'assistant.message',
  data: {
    'content': content,
    'messageId': messageId,
    'toolRequests': <dynamic>[],
    if (outputTokens != null) 'outputTokens': outputTokens,
  },
);

ChatEvent _assistantMessageStart({String messageId = 'msg-1'}) => ChatEvent(
  type: ChatEventType.assistantMessageStart,
  rawType: 'assistant.message_start',
  data: {'messageId': messageId},
);

ChatEvent _toolComplete({
  String toolCallId = 'tool-1',
  String toolName = 'read_file',
  String content = 'done',
  bool success = true,
}) => ChatEvent(
  type: ChatEventType.toolComplete,
  rawType: 'tool.execution_complete',
  data: {
    'toolCallId': toolCallId,
    'toolName': toolName,
    'result': {'content': content},
    'success': success,
  },
);

ChatEvent _resultEvent({
  int outputTokens = 7,
  int premiumRequests = 1,
  int totalApiDurationMs = 11,
  int sessionDurationMs = 12,
  int linesAdded = 2,
  int linesRemoved = 1,
}) => ChatEvent(
  type: ChatEventType.result,
  rawType: 'result',
  data: {
    'usage': {
      'outputTokens': outputTokens,
      'premiumRequests': premiumRequests,
      'totalApiDurationMs': totalApiDurationMs,
      'sessionDurationMs': sessionDurationMs,
      'codeChanges': {'linesAdded': linesAdded, 'linesRemoved': linesRemoved},
    },
  },
);

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSessionManager manager;
  late List<FakeChatProvider> createdProviders;

  FakeChatProvider createProvider(String providerId) {
    final provider = FakeChatProvider(id: providerId);
    createdProviders.add(provider);
    return provider;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    createdProviders = [];
    manager = ChatSessionManager.testInstance(providerFactory: createProvider);
  });

  tearDown(() {
    manager.disposeAll();
  });

  group('ChatSessionManager', () {
    test('getOrCreate creates and reuses sessions', () {
      final s1 = manager.getOrCreate('p1', _config());
      final s2 = manager.getOrCreate('p1', _config());

      expect(s1.panelId, 'p1');
      expect(identical(s1, s2), true);
      expect(manager.has('p1'), true);
      expect(manager.activeSessionIds, contains('p1'));
      expect(createdProviders.single.providerId, 'copilot');
    });

    test('get returns null for unknown panel', () {
      expect(manager.get('unknown'), isNull);
    });

    test('remove disposes session provider', () {
      manager.getOrCreate('p1', _config());
      final provider = createdProviders.single;

      manager.remove('p1');

      expect(manager.has('p1'), false);
      expect(provider.disposed, true);
    });

    test('disposeAll clears all sessions', () {
      manager.getOrCreate('p1', _config());
      manager.getOrCreate('p2', _config(provider: 'cursor'));

      manager.disposeAll();

      expect(manager.activeSessionIds, isEmpty);
      expect(createdProviders.every((provider) => provider.disposed), true);
    });

    test('detach keeps session alive without disposing provider', () {
      final session = manager.getOrCreate('p1', _config());
      final provider = session.provider as FakeChatProvider;

      manager.detach('p1');

      expect(manager.has('p1'), true);
      expect(manager.get('p1'), same(session));
      expect(provider.disposed, false);
      expect(provider.detached, false);
    });

    test('getOrCreate updates config on existing session', () {
      final session = manager.getOrCreate('p1', _config());

      final updated = manager.getOrCreate(
        'p1',
        _config().copyWith(model: 'new-model'),
      );

      expect(updated, same(session));
      expect(updated.config.model, 'new-model');
      expect(createdProviders.length, 1);
    });
  });

  group('ChatSession', () {
    late FakeChatProvider provider;
    late ChatSession session;

    setUp(() {
      provider = FakeChatProvider();
      session = ChatSession(
        panelId: 'p1',
        config: _config(),
        providerFactory: (_) => provider,
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('initial state', () {
      expect(session.messages, isEmpty);
      expect(session.isProcessing, false);
      expect(session.isFirstMessage, true);
      expect(session.streamingContent, '');
      expect(session.totalOutputTokens, 0);
      expect(session.lastUsage, isNull);
    });

    test('restoreMessages populates list and token totals', () {
      session.restoreMessages([
        {'id': 'msg-1', 'role': 'user', 'content': 'hello'},
        {
          'id': 'msg-2',
          'role': 'assistant',
          'content': 'hi there',
          'tokenUsage': {'outputTokens': 3},
        },
      ]);

      expect(session.messages.length, 2);
      expect(session.messages[0].role, ChatRole.user);
      expect(session.messages[1].role, ChatRole.assistant);
      expect(session.isFirstMessage, false);
      expect(session.totalOutputTokens, 3);
    });

    test('clearMessages resets state', () {
      session.restoreMessages([
        {
          'id': 'msg-1',
          'role': 'assistant',
          'content': 'hello',
          'tokenUsage': {'outputTokens': 4},
        },
      ]);
      session.restoreLastUsage({'outputTokens': 5});

      session.clearMessages();

      expect(session.messages, isEmpty);
      expect(session.isFirstMessage, true);
      expect(session.totalOutputTokens, 0);
      expect(session.lastUsage, isNull);
    });

    test('sendMessage rejects empty text and concurrent sends', () async {
      expect(await session.sendMessage(text: ''), false);
      expect(await session.sendMessage(text: '   '), false);

      expect(await session.sendMessage(text: 'first'), true);
      expect(session.isProcessing, true);
      expect(await session.sendMessage(text: 'second'), false);
    });

    test('sendMessage adds user message and forwards parsed payload', () async {
      final runtimeContext = ChatRuntimeContext(panelId: 'runtime-panel');

      final ok = await session.sendMessage(
        text: 'hello /notes.txt /image.png',
        attachments: const ['/extra.jpg', '/document.md'],
        runtimeContext: runtimeContext,
      );

      expect(ok, true);
      expect(session.messages.single.role, ChatRole.user);
      expect(session.messages.single.content, 'hello');
      expect(session.messages.single.attachments, const [
        '/extra.jpg',
        '/document.md',
        '/notes.txt',
        '/image.png',
      ]);
      expect(provider.sentMessages.single, 'hello');
      expect(provider.sentIsFirstMessages.single, true);
      expect(provider.sentAttachments.single, const [
        '/extra.jpg',
        '/image.png',
      ]);
      expect(provider.sentRuntimeContexts.single, same(runtimeContext));
    });

    test('sendMessage inlines yoloit_clip chat export and drops log dumps', () async {
      final clipDir = Directory('${PlatformDirs.instance.tempDir}/yoloit_clip');
      await clipDir.create(recursive: true);
      final chatClip = File('${clipDir.path}/clip_1782557969509.txt');
      final logClip = File('${clipDir.path}/clip_1782557974961.txt');
      await chatClip.writeAsString('''
[2026-06-26T13:35:52.568270] USER
добавь мне тестовых данных сюда

[2026-06-26T13:35:59.720499] ASSISTANT
Готово!
''');
      await logClip.writeAsString(
        'Launching lib/main.dart on macOS in debug mode...\n'
        'flutter: [BoardView] Canvas background pointer down\n',
      );

      final ok = await session.sendMessage(
        text: '${chatClip.path} ${logClip.path}',
      );

      expect(ok, true);
      expect(session.messages.single.attachments, [chatClip.path]);
      expect(
        session.messages.single.content,
        contains('добавь мне тестовых данных сюда'),
      );
      expect(provider.sentMessages.single, contains('добавь мне тестовых данных'));
      expect(provider.sentMessages.single, isNot(contains('Launching lib/main.dart')));
    });

    test('updateConfig notifies listeners and swaps provider', () {
      final providers = <FakeChatProvider>[];
      final swapSession = ChatSession(
        panelId: 'p1',
        config: _config(),
        providerFactory: (providerId) {
          final fake = FakeChatProvider(id: providerId);
          providers.add(fake);
          return fake;
        },
      );
      addTearDown(swapSession.dispose);
      swapSession.restoreOpencodeSessionId('oc-1');
      var notified = false;
      swapSession.addListener(() => notified = true);

      swapSession.updateConfig(
        _config(provider: 'opencode').copyWith(model: 'new'),
      );

      final firstProvider = providers.first;
      final nextProvider = swapSession.provider as FakeChatProvider;
      expect(notified, true);
      expect(nextProvider, isNot(same(firstProvider)));
      expect(firstProvider.disposed, true);
      expect(nextProvider.getSessionId('test-session'), 'oc-1');
      expect(swapSession.config.provider, 'opencode');
      expect(swapSession.config.model, 'new');
    });

    test(
      'serializeState includes config messages usage and provider session ids',
      () {
        session.restoreMessages([
          {'id': 'msg-1', 'role': 'user', 'content': 'hello'},
        ]);
        session.restoreLastUsage({'outputTokens': 9});
        session.restoreOpencodeSessionId('oc-session-123');
        session.restoreCopilotSessionId('copilot-session-123');
        session.restoreCursorSessionId('cursor-session-123');

        final state = session.serializeState();

        expect(state['config'], isA<Map<String, dynamic>>());
        expect(state['messages'], isA<List>());
        expect((state['messages'] as List).length, 1);
        expect(state['lastUsage'], isA<Map<String, dynamic>>());
        expect(state['opencodeSessionId'], 'oc-session-123');
        expect(state['copilotSessionId'], 'copilot-session-123');
        expect(state['cursorSessionId'], 'cursor-session-123');
        expect(state['config']['opencodeSessionId'], 'oc-session-123');
        expect(state['config']['copilotSessionId'], 'copilot-session-123');
        expect(state['config']['cursorSessionId'], 'cursor-session-123');
      },
    );

    test('restoreOpencodeSessionId stores id on opencode provider', () {
      final opencodeProvider = FakeChatProvider(id: 'opencode');
      final opencodeSession = ChatSession(
        panelId: 'p1',
        config: _config(provider: 'opencode'),
        providerFactory: (_) => opencodeProvider,
      );
      addTearDown(opencodeSession.dispose);

      opencodeSession.restoreOpencodeSessionId('oc-session-123');

      expect(opencodeSession.opencodeSessionId, 'oc-session-123');
      expect(opencodeProvider.getSessionId('test-session'), 'oc-session-123');
    });

    test('restoreCopilotSessionId stores id on copilot provider', () {
      final copilotProvider = FakeChatProvider(id: 'copilot');
      final copilotSession = ChatSession(
        panelId: 'p1',
        config: _config(provider: 'copilot'),
        providerFactory: (_) => copilotProvider,
      );
      addTearDown(copilotSession.dispose);

      copilotSession.restoreCopilotSessionId('copilot-session-123');

      expect(copilotSession.copilotSessionId, 'copilot-session-123');
      expect(
        copilotProvider.getSessionId('test-session'),
        'copilot-session-123',
      );
    });

    test('restoreCursorSessionId stores id on cursor provider', () {
      final cursorProvider = FakeChatProvider(id: 'cursor');
      final cursorSession = ChatSession(
        panelId: 'p1',
        config: _config(provider: 'cursor'),
        providerFactory: (_) => cursorProvider,
      );
      addTearDown(cursorSession.dispose);

      cursorSession.restoreCursorSessionId('cursor-session-123');

      expect(cursorSession.cursorSessionId, 'cursor-session-123');
      expect(cursorProvider.getSessionId('test-session'), 'cursor-session-123');
    });

    test(
      'updateConfig rebinds copilot session id when session name changes',
      () {
        final copilotProvider = FakeChatProvider(id: 'copilot');
        final copilotSession = ChatSession(
          panelId: 'p1',
          config: _config(provider: 'copilot'),
          providerFactory: (_) => copilotProvider,
        );
        addTearDown(copilotSession.dispose);
        copilotSession.restoreCopilotSessionId('copilot-session-123');

        copilotSession.updateConfig(
          _config(provider: 'copilot').copyWith(sessionName: 'test-session 2'),
        );

        expect(
          copilotProvider.getSessionId('test-session 2'),
          'copilot-session-123',
        );
      },
    );

    test(
      'updateConfig rebinds cursor session id when session name changes',
      () {
        final cursorProvider = FakeChatProvider(id: 'cursor');
        final cursorSession = ChatSession(
          panelId: 'p1',
          config: _config(provider: 'cursor'),
          providerFactory: (_) => cursorProvider,
        );
        addTearDown(cursorSession.dispose);
        cursorSession.restoreCursorSessionId('cursor-session-123');

        cursorSession.updateConfig(
          _config(provider: 'cursor').copyWith(sessionName: 'test-session 2'),
        );

        expect(
          cursorProvider.getSessionId('test-session 2'),
          'cursor-session-123',
        );
      },
    );
  });

  group('ChatSession event processing', () {
    late FakeChatProvider provider;
    late ChatSession session;

    setUp(() {
      provider = FakeChatProvider();
      session = ChatSession(
        panelId: 'p1',
        config: _config(),
        providerFactory: (_) => provider,
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('processes assistant streaming into final message', () async {
      await session.sendMessage(text: 'hello');
      provider.emitEvent(_assistantMessageStart());
      provider.emitEvent(_assistantDelta('Hi'));
      provider.emitEvent(_assistantDelta(' there'));
      provider.emitEvent(_assistantMessage('Hi there', outputTokens: 5));
      await provider.complete();
      await _flushEvents();

      expect(session.isProcessing, false);
      expect(session.streamingContent, '');
      expect(session.messages.length, 2);
      expect(session.messages.last.role, ChatRole.assistant);
      expect(session.messages.last.content, 'Hi there');
      expect(session.totalOutputTokens, 5);
    });

    test('records tool completion and result usage', () async {
      await session.sendMessage(text: 'hello');
      provider.emitEvent(_toolComplete(content: 'tool output'));
      provider.emitEvent(_resultEvent(outputTokens: 7, linesAdded: 4));
      await provider.complete();
      await _flushEvents();

      expect(session.messages.length, 2);
      expect(session.messages.last.role, ChatRole.tool);
      expect(session.messages.last.content, 'tool output');
      expect(session.messages.last.metadata?['success'], true);
      expect(session.lastUsage?.outputTokens, 7);
      expect(session.lastUsage?.linesAdded, 4);
      expect(session.totalOutputTokens, 7);
    });

    test('keeps assistant message above tools when tools arrive first', () async {
      await session.sendMessage(text: 'hello');
      provider.emitEvent(
        _toolComplete(
          toolCallId: 'tool-a',
          toolName: 'board.apply',
          content: 'applied',
        ),
      );
      provider.emitEvent(_assistantMessageStart(messageId: 'msg-a'));
      provider.emitEvent(_assistantDelta('Done'));
      provider.emitEvent(_assistantMessage('Done', messageId: 'msg-a'));
      await provider.complete();
      await _flushEvents();

      expect(session.messages.length, 3);
      expect(session.messages[1].role, ChatRole.assistant);
      expect(session.messages[1].content, 'Done');
      expect(session.messages[2].role, ChatRole.tool);
      expect(session.messages[2].toolName, 'board.apply');
    });

    test('adds system error message on provider error', () async {
      await session.sendMessage(text: 'hello');
      provider.emitError(Exception('boom'));
      await _flushEvents();

      expect(session.isProcessing, false);
      expect(session.messages.length, 2);
      expect(session.messages.last.role, ChatRole.system);
      expect(session.messages.last.content, contains('boom'));
    });

    test(
      'stopStreaming finalizes partial content and stops provider',
      () async {
        await session.sendMessage(text: 'hello');
        provider.emitEvent(_assistantMessageStart());
        provider.emitEvent(_assistantDelta('partial reply'));
        await _flushEvents();

        await session.stopStreaming();

        expect(provider.stopped, true);
        expect(session.isProcessing, false);
        expect(session.streamingContent, '');
        expect(session.messages.length, 2);
        expect(session.messages.last.content, 'partial reply');
      },
    );

    test('sendAndWait resolves with final messages', () async {
      final future = session.sendAndWait(text: 'hello');
      provider.emitEvent(_assistantMessageStart());
      provider.emitEvent(_assistantDelta('done'));
      provider.emitEvent(_assistantMessage('done'));
      await provider.complete();

      final messages = await future;

      expect(messages.length, 2);
      expect(messages.last.content, 'done');
      expect(session.isProcessing, false);
    });

    test(
      'sendAndWait returns existing messages when send is rejected',
      () async {
        await session.sendMessage(text: 'first');

        final messages = await session.sendAndWait(text: 'second');

        expect(messages.length, 1);
        expect(messages.single.content, 'first');
      },
    );

    test('captures opencode session id after completion', () async {
      final opencodeProvider = FakeChatProvider(id: 'opencode');
      final opencodeSession = ChatSession(
        panelId: 'p1',
        config: _config(provider: 'opencode'),
        providerFactory: (_) => opencodeProvider,
      );
      addTearDown(opencodeSession.dispose);

      final future = opencodeSession.sendAndWait(text: 'hello');
      opencodeProvider.setSessionId('test-session', 'oc-live-1');
      await opencodeProvider.complete();
      await future;

      expect(opencodeSession.opencodeSessionId, 'oc-live-1');
    });

    test(
      'captures copilot session id and resumes with it on next send',
      () async {
        final copilotProvider = FakeChatProvider(id: 'copilot');
        final copilotSession = ChatSession(
          panelId: 'p1',
          config: _config(provider: 'copilot'),
          providerFactory: (_) => copilotProvider,
        );
        addTearDown(copilotSession.dispose);

        final firstFuture = copilotSession.sendAndWait(text: 'hello');
        copilotProvider.setSessionId('test-session', 'copilot-live-1');
        await copilotProvider.complete();
        await firstFuture;

        expect(copilotSession.copilotSessionId, 'copilot-live-1');
        expect(copilotProvider.sentIsFirstMessages, [true]);

        final secondFuture = copilotSession.sendAndWait(text: 'resume');
        expect(copilotProvider.getSessionId('test-session'), 'copilot-live-1');
        copilotProvider.setSessionId('test-session', 'copilot-live-1');
        await copilotProvider.complete();
        await secondFuture;

        expect(copilotProvider.sentIsFirstMessages, [true, false]);
      },
    );

    test(
      'captures cursor session id and resumes with it on next send',
      () async {
        final cursorProvider = FakeChatProvider(id: 'cursor');
        final cursorSession = ChatSession(
          panelId: 'p1',
          config: _config(provider: 'cursor'),
          providerFactory: (_) => cursorProvider,
        );
        addTearDown(cursorSession.dispose);

        final firstFuture = cursorSession.sendAndWait(text: 'hello');
        cursorProvider.setSessionId('test-session', 'cursor-live-1');
        await cursorProvider.complete();
        await firstFuture;

        expect(cursorSession.cursorSessionId, 'cursor-live-1');
        expect(cursorProvider.sentIsFirstMessages, [true]);

        final secondFuture = cursorSession.sendAndWait(text: 'resume');
        expect(cursorProvider.getSessionId('test-session'), 'cursor-live-1');
        cursorProvider.setSessionId('test-session', 'cursor-live-1');
        await cursorProvider.complete();
        await secondFuture;

        expect(cursorProvider.sentIsFirstMessages, [true, false]);
      },
    );
  });

  group('syncFromWidget', () {
    test('overwrites session state with widget state', () {
      SharedPreferences.setMockInitialValues({});
      final manager = ChatSessionManager.testInstance(
        providerFactory: (_) => FakeChatProvider(),
      );
      final session = manager.getOrCreate(
        'sync-panel',
        const ChatSessionConfig(sessionName: 'sess', workingDir: '/tmp'),
      );

      // Session starts empty
      expect(session.messages, isEmpty);
      expect(session.isFirstMessage, isTrue);

      // Sync widget state into session
      final msgs = [
        ChatMessage(
          id: 'u1',
          role: ChatRole.user,
          content: 'hi',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          content: 'hello',
          timestamp: DateTime(2026),
        ),
      ];
      session.syncFromWidget(
        messages: msgs,
        isFirstMessage: false,
        totalOutputTokens: 42,
        opencodeSessionId: 'oc-123',
        copilotSessionId: 'copilot-123',
        cursorSessionId: 'cursor-123',
      );

      expect(session.messages.length, 2);
      expect(session.messages[0].content, 'hi');
      expect(session.messages[1].content, 'hello');
      expect(session.isFirstMessage, isFalse);
      expect(session.totalOutputTokens, 42);
      expect(session.opencodeSessionId, 'oc-123');
      expect(session.copilotSessionId, 'copilot-123');
      expect(session.cursorSessionId, 'cursor-123');
    });

    test('session survives detach and returns synced state on re-mount', () {
      SharedPreferences.setMockInitialValues({});
      final manager = ChatSessionManager.testInstance(
        providerFactory: (_) => FakeChatProvider(),
      );
      final config = const ChatSessionConfig(
        sessionName: 's',
        workingDir: '/d',
      );
      final session = manager.getOrCreate('panel-A', config);

      // Simulate widget lifecycle: send messages, then dispose
      final msgs = [
        ChatMessage(
          id: 'u1',
          role: ChatRole.user,
          content: 'question',
          timestamp: DateTime(2026),
        ),
        ChatMessage(
          id: 'a1',
          role: ChatRole.assistant,
          content: 'answer',
          timestamp: DateTime(2026),
        ),
      ];
      session.syncFromWidget(messages: msgs, isFirstMessage: false);
      manager.detach('panel-A');

      // Re-mount: getOrCreate returns the same session with messages
      final same = manager.getOrCreate('panel-A', config);
      expect(identical(same, session), isTrue);
      expect(same.messages.length, 2);
      expect(same.messages[0].content, 'question');
      expect(same.messages[1].content, 'answer');
      expect(same.isFirstMessage, isFalse);
    });
  });
}
