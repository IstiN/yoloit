import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/chat_session_core.dart';
import 'package:yoloit/features/board/model/chat_models.dart';

class _FakeChatProvider extends ChatProvider {
  // ignore: close_sinks — closed by complete().
  StreamController<ChatEvent>? _controller;

  @override
  String get providerId => 'fake';

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
    _controller = StreamController<ChatEvent>();
    return _controller!.stream;
  }

  Future<void> complete() async {
    final controller = _controller;
    _controller = null;
    await controller?.close();
  }

  @override
  Future<void> stop(String sessionName) async {}

  @override
  Future<void> dispose() async {}
}

ChatSessionConfig _config() => const ChatSessionConfig(
  sessionName: 'test-session',
  workingDir: '/tmp',
  provider: 'fake',
);

Map<String, dynamic> _msgJson(int i) => {
  'id': 'msg-$i',
  'role': i.isEven ? 'user' : 'assistant',
  'content': 'message $i',
};

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ChatSession messages getter', () {
    late ChatSession session;

    setUp(() {
      session = ChatSession(
        panelId: 'p1',
        config: _config(),
        providerFactory: (_) => _FakeChatProvider(),
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('returns identical content and is unmodifiable', () {
      session.restoreMessages([_msgJson(0), _msgJson(1)]);
      final view = session.messages;
      expect(view.length, 2);
      expect(view.map((m) => m.id).toList(), ['msg-0', 'msg-1']);
      expect(
        () => view.add(
          const ChatMessage(
            id: 'x',
            role: ChatRole.user,
            content: 'nope',
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('snapshot is not rebuilt on repeated access', () {
      session.restoreMessages([_msgJson(0)]);
      final a = session.messages;
      final b = session.messages;
      expect(identical(a, b), isTrue);
    });

    test('snapshot is invalidated on mutation', () {
      session.restoreMessages([_msgJson(0)]);
      final before = session.messages;
      session.restoreMessages([_msgJson(1)]);
      final after = session.messages;
      expect(identical(before, after), isFalse);
      expect(after.map((m) => m.id).toList(), ['msg-0', 'msg-1']);
    });

    test('clearMessages invalidates the snapshot', () {
      session.restoreMessages([_msgJson(0)]);
      final before = session.messages;
      session.clearMessages();
      expect(identical(before, session.messages), isFalse);
      expect(session.messages, isEmpty);
    });
  });

  group('ChatSession in-memory history cap', () {
    late ChatSession session;

    setUp(() {
      session = ChatSession(
        panelId: 'p1',
        config: _config(),
        providerFactory: (_) => _FakeChatProvider(),
      );
    });

    tearDown(() {
      session.dispose();
    });

    test('restoreMessages beyond cap keeps most recent 500 in order', () {
      final saved = List.generate(600, _msgJson);
      session.restoreMessages(saved);
      expect(session.messages.length, 500);
      // Same policy as the serialization trim: drop the oldest, keep the
      // most recent N; no role is protected.
      expect(session.messages.first.id, 'msg-100');
      expect(session.messages.last.id, 'msg-599');
      expect(
        session.messages.map((m) => m.id).toList(),
        List.generate(500, (i) => 'msg-${i + 100}'),
      );
    });

    test('roles are not specially protected from trimming', () {
      final saved = List.generate(500, (i) => {
        'id': 'sys-$i',
        'role': 'system',
        'content': 'system $i',
      });
      session.restoreMessages(saved);
      session.restoreMessages([_msgJson(999)]);
      // The oldest system message is dropped just like any other message.
      expect(session.messages.length, 500);
      expect(session.messages.first.id, 'sys-1');
      expect(session.messages.last.id, 'msg-999');
    });

    test('append via sendMessage beyond cap trims the oldest message', () async {
      session.restoreMessages(List.generate(500, _msgJson));
      expect(session.messages.length, 500);

      final ok = await session.sendMessage(text: 'one more');
      expect(ok, isTrue);
      expect(session.messages.length, 500);
      expect(session.messages.first.id, 'msg-1');
      expect(session.messages.last.role, ChatRole.user);
      expect(session.messages.last.content, 'one more');
    });

    test('tool messages keep relative order after trimming', () {
      final saved = <Map<String, dynamic>>[
        for (var i = 0; i < 499; i++) _msgJson(i),
        {
          'id': 'tool-1',
          'role': 'tool',
          'content': 'result',
          'toolCallId': 'call-1',
        },
      ];
      session.restoreMessages(saved);
      session.restoreMessages([_msgJson(999)]);
      expect(session.messages.length, 500);
      // Front-trim preserves relative order of everything kept (501
      // restored, oldest one dropped).
      expect(
        session.messages.map((m) => m.id).toList(),
        [...List.generate(498, (i) => 'msg-${i + 1}'), 'tool-1', 'msg-999'],
      );
    });
  });
}
