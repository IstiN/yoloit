import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// Tool executor fake that records invocations and always succeeds.
class _FakeToolExecutor implements YoloitToolExecutor {
  final List<({String name, Map<String, Object?> args})> calls = [];

  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
    bool argumentsPreNormalized = false,
  }) async {
    calls.add((
      name: functionName,
      args: Map<String, Object?>.from(arguments),
    ));
    return jsonEncode(<String, Object?>{
      'ok': true,
      'command': 'yoloit $functionName',
    });
  }
}

/// Binds a loopback HTTP server, retrying to survive parallel test load.
Future<HttpServer> _bindWithRetry() async {
  Object? lastError;
  for (var attempt = 0; attempt < 5; attempt++) {
    try {
      return await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    } catch (e) {
      lastError = e;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }
  throw StateError('could not bind test server: $lastError');
}

/// Serves JSON POST requests, recording decoded bodies and answering with
/// the SSE payload produced by [respond].
void _serveSse(
  HttpServer server,
  List<Map<String, dynamic>> requests,
  String Function(int index, Map<String, dynamic> body) respond,
) {
  unawaited(() async {
    await for (final request in server) {
      final body =
          jsonDecode(await utf8.decoder.bind(request).join())
              as Map<String, dynamic>;
      requests.add(body);
      request.response
        ..headers.contentType = ContentType('text', 'event-stream')
        ..write(respond(requests.length - 1, body));
      await request.response.close();
    }
  }());
}

String _sse(List<String> dataPayloads) {
  final buffer = StringBuffer();
  for (final payload in dataPayloads) {
    buffer.write('data: $payload\n\n');
  }
  buffer.write('data: [DONE]\n\n');
  return buffer.toString();
}

String _textResponse(String text) => _sse([
  jsonEncode({
    'choices': [
      {
        'delta': {'content': text},
      },
    ],
  }),
]);

CloudLlmConfig _configFor(HttpServer server) => CloudLlmConfig(
  id: 'test',
  name: 'Test',
  baseUrl: 'http://${server.address.host}:${server.port}',
  apiKey: 'key',
  model: 'test-model',
);

List<Map<String, dynamic>> _messagesOf(Map<String, dynamic> request) =>
    (request['messages'] as List).cast<Map<String, dynamic>>();

void main() {
  group('CloudLlmProvider', () {
    late HttpServer server;
    late List<Map<String, dynamic>> requests;
    late _FakeToolExecutor executor;
    late CloudLlmProvider provider;

    Future<void> startServer(
      String Function(int index, Map<String, dynamic> body) respond,
    ) async {
      server = await _bindWithRetry();
      requests = <Map<String, dynamic>>[];
      _serveSse(server, requests, respond);
      executor = _FakeToolExecutor();
      provider = CloudLlmProvider(
        config: _configFor(server),
        toolExecutor: executor,
      );
    }

    tearDown(() async {
      await server.close();
    });

    Future<List<ChatEvent>> send({
      String message = 'hello',
      ChatRuntimeContext? runtimeContext,
      List<Map<String, Object?>>? audioContentOverride,
    }) {
      return provider
          .sendMessage(
            message: message,
            config: const ChatSessionConfig(
              sessionName: 's1',
              workingDir: '/tmp',
            ),
            isFirstMessage: true,
            runtimeContext: runtimeContext,
            audioContentOverride: audioContentOverride,
          )
          .toList();
    }

    test('appends full board/panel context to the system prompt', () async {
      await HttpOverrides.runZoned(() async {
        await startServer((_, __) => _textResponse('ok'));

        final events = await send(
          runtimeContext: const ChatRuntimeContext(
            boardId: 'board-1',
            boardName: 'Test Board',
            panelId: 'p1',
            panelTitle: 'Chat',
            panelType: 'board.chat',
          ),
        );

        final system = _messagesOf(requests.single).first['content'] as String;
        expect(system, contains('Current context:'));
        expect(system, contains('- Board: Test Board (id: board-1)'));
        expect(system, contains('- Panel: Chat (id: p1)'));
        expect(system, contains('- Panel type: board.chat'));
        expect(
          system,
          contains('Use this board/panel as default'),
        );

        final user = _messagesOf(requests.single).last;
        expect(user['role'], 'user');
        expect(user['content'], 'hello');

        expect(
          events.last.type,
          ChatEventType.result,
        );
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('falls back to board id when the name is missing', () async {
      await HttpOverrides.runZoned(() async {
        await startServer((_, __) => _textResponse('ok'));

        await send(
          runtimeContext: const ChatRuntimeContext(boardId: 'b-9'),
        );

        final system = _messagesOf(requests.single).first['content'] as String;
        expect(system, contains('- Board: b-9 (id: b-9)'));
        expect(system, isNot(contains('- Panel:')));
        expect(system, isNot(contains('- Panel type:')));
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('omits the context section without runtime context', () async {
      await HttpOverrides.runZoned(() async {
        await startServer((_, __) => _textResponse('ok'));

        await send();

        final system = _messagesOf(requests.single).first['content'] as String;
        expect(system, isNot(contains('Current context:')));
        expect(system, contains('You are YoLo Assistant.'));
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('sends a multimodal user message with a board snapshot', () async {
      await HttpOverrides.runZoned(() async {
        await startServer((_, __) => _textResponse('ok'));

        await send(
          runtimeContext: const ChatRuntimeContext(
            boardId: 'board-1',
            boardSnapshotBase64: 'QUJD',
          ),
        );

        final user = _messagesOf(requests.single).last;
        final content = user['content'] as List;
        expect(content, hasLength(2));
        expect(
          content[0],
          <String, Object?>{'type': 'text', 'text': 'hello'},
        );
        final image = content[1] as Map<String, dynamic>;
        expect(image['type'], 'image_url');
        expect(
          (image['image_url'] as Map<String, dynamic>)['url'],
          'data:image/png;base64,QUJD',
        );
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('audio content override wins over text and snapshot', () async {
      await HttpOverrides.runZoned(() async {
        await startServer((_, __) => _textResponse('transcribed'));

        final audio = <Map<String, Object?>>[
          {
            'type': 'input_audio',
            'input_audio': {'data': 'AA==', 'format': 'wav'},
          },
        ];
        await send(
          runtimeContext: const ChatRuntimeContext(
            boardSnapshotBase64: 'QUJD',
          ),
          audioContentOverride: audio,
        );

        final user = _messagesOf(requests.single).last;
        expect(user['content'], audio);
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('accumulates legacy function_call fragments into a tool call',
        () async {
      await HttpOverrides.runZoned(() async {
        await startServer((index, _) {
          if (index == 0) {
            return _sse([
              jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'function_call': {'name': 'yoloit_boa'},
                    },
                  },
                ],
              }),
              jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'function_call': {'name': 'rds'},
                    },
                  },
                ],
              }),
              jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'function_call': {'arguments': '{}'},
                    },
                  },
                ],
              }),
            ]);
          }
          return _textResponse('All done');
        });

        final events = await send();

        // Name fragments were merged into a single tool call.
        expect(executor.calls, hasLength(1));
        expect(executor.calls.single.name, 'yoloit_boards');

        final toolStart = events.firstWhere(
          (e) => e.type == ChatEventType.toolStart,
        );
        expect(toolStart.data['toolName'], 'yoloit_boards');
        final toolComplete = events.firstWhere(
          (e) => e.type == ChatEventType.toolComplete,
        );
        expect(toolComplete.data['success'], isTrue);

        // The agentic loop issued a second request carrying the tool result.
        expect(requests, hasLength(2));
        final followUp = _messagesOf(requests[1]);
        expect(
          followUp.any((m) => m['role'] == 'assistant' && m['tool_calls'] != null),
          isTrue,
        );
        final toolMessage = followUp.firstWhere((m) => m['role'] == 'tool');
        expect(toolMessage['content'] as String, contains('"ok":true'));

        // Final assistant message contains the follow-up text.
        final finalMessage = events.lastWhere(
          (e) => e.type == ChatEventType.assistantMessage,
        );
        expect(finalMessage.data['content'], 'All done');
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));
  });
}

final class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}
