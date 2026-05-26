import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_manager.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

/// Fake provider that records all calls.
class _FakeProvider extends ChatProvider {
  _FakeProvider({this.id = 'copilot', this.fakeImageMode = ChatImageMode.filePath});

  final String id;
  final ChatImageMode fakeImageMode;
  final List<String> sentMessages = [];
  final List<List<String>> sentAttachments = [];
  final List<ChatRuntimeContext?> sentContexts = [];
  StreamController<ChatEvent>? _controller;
  bool disposed = false;

  @override
  String get providerId => id;

  @override
  String get displayName => id;

  @override
  List<ChatModelInfo> get availableModels => const [];

  @override
  bool get supportsImages => true;

  @override
  ChatImageMode get imageMode => fakeImageMode;

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
    sentContexts.add(runtimeContext);
    _controller = StreamController<ChatEvent>();
    return _controller!.stream;
  }

  void emitDone() {
    _controller?.close();
    _controller = null;
  }

  @override
  Future<void> stop(String sessionName) async {
    await _controller?.close();
    _controller = null;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller?.close());
  }

  @override
  void detach() {}

  @override
  void setSessionId(String sessionName, String sessionId) {}

  @override
  String? getSessionId(String sessionName) => null;
}

const _workingDir = '/tmp/test';

ChatSessionConfig _config({String provider = 'copilot'}) => ChatSessionConfig(
  sessionName: 'test-session',
  workingDir: _workingDir,
  provider: provider,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ChatSessionManager manager;
  late List<_FakeProvider> createdProviders;

  _FakeProvider createProvider(String providerId) {
    final provider = _FakeProvider(id: providerId);
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

  group('ChatSession — board snapshot injection', () {
    test('snapshot path is injected into attachments for CLI agents', () {
      final session = manager.getOrCreate('p1', _config());
      const context = ChatRuntimeContext(
        boardSnapshotPath: '/tmp/snapshot.png',
      );

      session.sendMessage(text: 'hello', runtimeContext: context);

      final provider = createdProviders.single;
      expect(provider.sentMessages, ['hello']);
      // The snapshot path should be added to attachments
      expect(provider.sentAttachments.last, contains('/tmp/snapshot.png'));
    });

    test('snapshot path is NOT injected when null', () {
      final session = manager.getOrCreate('p2', _config());
      const context = ChatRuntimeContext();

      session.sendMessage(text: 'hello', runtimeContext: context);

      final provider = createdProviders.single;
      expect(provider.sentAttachments.last, isEmpty);
    });

    test('snapshot path is NOT injected for base64 providers', () {
      // Create a manager with base64 provider
      final base64Provider = _FakeProvider(
        id: 'yolochat',
        fakeImageMode: ChatImageMode.base64,
      );
      final mgr = ChatSessionManager.testInstance(
        providerFactory: (_) => base64Provider,
      );

      final session = mgr.getOrCreate('p3', _config(provider: 'yolochat'));
      const context = ChatRuntimeContext(
        boardSnapshotPath: '/tmp/snapshot.png',
        boardSnapshotBase64: 'iVBORw0KGgoAAAANSUhEUg==',
      );

      session.sendMessage(text: 'hello', runtimeContext: context);

      // base64 provider should NOT get the file path as attachment
      expect(
        base64Provider.sentAttachments.last,
        isNot(contains('/tmp/snapshot.png')),
      );

      mgr.disposeAll();
    });
  });

  group('ChatRuntimeContext', () {
    test('boardSnapshotPath field', () {
      const ctx = ChatRuntimeContext(boardSnapshotPath: '/tmp/snap.png');
      expect(ctx.boardSnapshotPath, '/tmp/snap.png');
      expect(ctx.boardSnapshotBase64, isNull);
    });

    test('boardSnapshotBase64 field', () {
      const ctx = ChatRuntimeContext(boardSnapshotBase64: 'abc123');
      expect(ctx.boardSnapshotBase64, 'abc123');
      expect(ctx.boardSnapshotPath, isNull);
    });

    test('both fields can be set', () {
      const ctx = ChatRuntimeContext(
        boardSnapshotPath: '/tmp/snap.png',
        boardSnapshotBase64: 'abc123',
      );
      expect(ctx.boardSnapshotPath, '/tmp/snap.png');
      expect(ctx.boardSnapshotBase64, 'abc123');
    });

    test('all original fields preserved', () {
      const ctx = ChatRuntimeContext(
        boardId: 'b1',
        boardName: 'My Board',
        panelId: 'p1',
        panelTitle: 'Chat',
        panelType: 'board.chat',
        viewportScale: 1.5,
      );
      expect(ctx.boardId, 'b1');
      expect(ctx.boardName, 'My Board');
      expect(ctx.panelId, 'p1');
      expect(ctx.panelTitle, 'Chat');
      expect(ctx.panelType, 'board.chat');
      expect(ctx.viewportScale, 1.5);
    });
  });
}
