import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager_web.dart' as web;
import 'package:yoloit/features/board/model/chat_models.dart';

class _FakeChatProvider extends ChatProvider {
  _FakeChatProvider({required this.providerId});

  @override
  final String providerId;

  @override
  String get displayName => 'Fake';

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => false;

  @override
  ChatImageMode get imageMode => ChatImageMode.base64;

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
    return Stream<ChatEvent>.empty();
  }

  @override
  Future<void> stop(String sessionName) async {}

  @override
  void dispose() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatSessionManager web', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('creates cloud provider for cloud: prefix', () {
      final manager = web.ChatSessionManager.testInstance(
        providerFactory: (id) => _FakeChatProvider(providerId: id),
      );
      addTearDown(manager.disposeAll);

      final session = manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          provider: 'cloud:test-cfg',
        ),
      );

      expect(session.provider.providerId, 'cloud:test-cfg');
      expect(session.config.provider, 'cloud:test-cfg');
    });

    test('non-cloud provider resolves to unsupported stub', () async {
      final manager = web.ChatSessionManager.testInstance();
      addTearDown(manager.disposeAll);

      final session = manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          provider: 'copilot',
        ),
      );

      expect(session.provider.displayName, 'Unsupported');
      expect(session.provider.availableModels, isEmpty);

      final stream = session.provider.sendMessage(
        message: 'hi',
        config: session.config,
        isFirstMessage: true,
      );
      await expectLater(
        stream,
        emitsError(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not supported in the browser'),
          ),
        ),
      );
    });

    test('getOrCreate reuses and updates existing session', () {
      final manager = web.ChatSessionManager.testInstance(
        providerFactory: (id) => _FakeChatProvider(providerId: id),
      );
      addTearDown(manager.disposeAll);

      final first = manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          provider: 'cloud:a',
        ),
      );
      final second = manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's2',
          workingDir: '/tmp',
          provider: 'cloud:a',
        ),
      );

      expect(identical(first, second), isTrue);
      expect(second.config.sessionName, 's2');
    });

    test('remove disposes session and clears it', () {
      final manager = web.ChatSessionManager.testInstance(
        providerFactory: (id) => _FakeChatProvider(providerId: id),
      );

      manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          provider: 'cloud:a',
        ),
      );
      expect(manager.has('panel-1'), isTrue);

      manager.remove('panel-1');
      expect(manager.has('panel-1'), isFalse);
      expect(manager.get('panel-1'), isNull);
    });

    test('disposeAll clears all sessions', () {
      final manager = web.ChatSessionManager.testInstance(
        providerFactory: (id) => _FakeChatProvider(providerId: id),
      );

      manager.getOrCreate(
        'panel-1',
        const ChatSessionConfig(
          sessionName: 's1',
          workingDir: '/tmp',
          provider: 'cloud:a',
        ),
      );
      manager.getOrCreate(
        'panel-2',
        const ChatSessionConfig(
          sessionName: 's2',
          workingDir: '/tmp',
          provider: 'cloud:b',
        ),
      );

      manager.disposeAll();

      expect(manager.activeSessionIds, isEmpty);
    });
  });
}
