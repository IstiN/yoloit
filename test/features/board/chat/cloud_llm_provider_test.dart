import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/cloud_llm_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';
import 'package:yoloit/features/board/model/chat_models.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

void main() {
  test('cloud provider replays generated tool-call ids across turns', () async {
    await HttpOverrides.runZoned(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);

      var requestCount = 0;
      unawaited(() async {
        await for (final request in server) {
          final body =
              jsonDecode(await utf8.decoder.bind(request).join())
                  as Map<String, Object?>;
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
            charset: 'utf-8',
          );

          if (requestCount == 0) {
            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {
                      'tool_calls': [
                        {
                          'index': 0,
                          'function': {'name': 'yoloit_board_focus', 'arguments': '{"id_or_name":"board-1"}'},
                        },
                      ],
                    },
                  },
                ],
              })}\n\n',
            );
          } else {
            final messages =
                (body['messages'] as List).cast<Map<String, Object?>>();
            final assistant = messages.firstWhere(
              (message) =>
                  message['role'] == 'assistant' &&
                  message['tool_calls'] != null,
            );
            final tool = messages.firstWhere(
              (message) => message['role'] == 'tool',
            );
            final toolCallIds =
                ((assistant['tool_calls'] as List)
                        .cast<Map<String, Object?>>()
                        .map((call) => call['id'])
                        .whereType<String>())
                    .toSet();

            expect(toolCallIds, isNotEmpty);
            expect(toolCallIds, contains(tool['tool_call_id']));

            request.response.write(
              'data: ${jsonEncode({
                'choices': [
                  {
                    'delta': {'content': requestCount == 1 ? 'first ok' : 'second ok'},
                  },
                ],
              })}\n\n',
            );
          }

          request.response.write('data: [DONE]\n\n');
          await request.response.close();
          requestCount++;
        }
      }());

      final provider = CloudLlmProvider(
        config: CloudLlmConfig(
          id: 'test-cloud',
          name: 'Test Cloud',
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'test-key',
          model: 'test-model',
        ),
        toolExecutor: _FakeToolExecutor(),
      );
      addTearDown(provider.dispose);

      Future<String> send(
        String message, {
        required bool isFirstMessage,
      }) async {
        final stream = provider.sendMessage(
          message: message,
          config: const ChatSessionConfig(
            sessionName: 'session-1',
            workingDir: '/tmp',
          ),
          isFirstMessage: isFirstMessage,
        );
        var reply = '';
        await for (final event in stream) {
          if (event.type == ChatEventType.assistantMessage) {
            reply = event.data['content'] as String? ?? '';
          }
        }
        return reply;
      }

      expect(
        await send('перейди на smoke board', isFirstMessage: true),
        'first ok',
      );
      expect(
        await send('open my test board', isFirstMessage: false),
        'second ok',
      );
      expect(requestCount, 3);
    }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
  });
}

final class _FakeToolExecutor implements YoloitToolExecutor {
  @override
  Future<String> invoke(
    String functionName,
    Map<String, Object?> arguments, {
    ChatRuntimeContext? runtimeContext,
  }) async => jsonEncode(<String, Object?>{'ok': true, 'tool': functionName});
}

final class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}
