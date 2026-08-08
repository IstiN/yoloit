import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/cloud_asr_http_client.dart';

void main() {
  group('buildChatAudioPayload', () {
    test('returns JSON with base64 audio and transcription prompt', () {
      final payload = buildChatAudioPayload(
        model: 'test-model',
        audioBytes: [1, 2, 3],
        format: 'wav',
      );

      final decoded = jsonDecode(payload) as Map<String, Object?>;
      expect(decoded['model'], 'test-model');

      final messages = (decoded['messages'] as List).cast<Map<String, Object?>>();
      expect(messages, hasLength(1));

      final content = (messages.first['content'] as List).cast<Map<String, Object?>>();
      expect(content, hasLength(2));

      final audioItem = content.firstWhere((c) => c['type'] == 'input_audio');
      final audioData = (audioItem['input_audio'] as Map<String, Object?>)['data'] as String;
      expect(audioData, base64Encode([1, 2, 3]));

      final textItem = content.firstWhere((c) => c['type'] == 'text');
      expect(textItem['text'], contains('Transcribe this audio'));
    });
  });

  group('postChatCompletion', () {
    test('returns trimmed content on success', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        unawaited(() async {
          await for (final request in server) {
            expect(
              request.headers.value(HttpHeaders.authorizationHeader),
              'Bearer test-key',
            );
            expect(
              request.headers.value(HttpHeaders.contentTypeHeader),
              'application/json',
            );
            expect(
              request.headers.value('X-Custom'),
              'custom-value',
            );

            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'choices': [
                {'message': {'content': '  Hello world  '}},
              ],
            }));
            await request.response.close();
          }
        }());

        final result = await postChatCompletion(
          baseUrl: 'http://${server.address.host}:${server.port}',
          apiKey: 'test-key',
          extraHeaders: const {'X-Custom': 'custom-value'},
          payload: '{}',
        );

        expect(result, 'Hello world');
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    });

    test('throws StateError on HTTP error', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        unawaited(() async {
          await for (final request in server) {
            request.response.statusCode = 500;
            request.response.write('server error');
            await request.response.close();
          }
        }());

        expect(
          () => postChatCompletion(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'key',
            extraHeaders: const {},
            payload: '{}',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('Cloud ASR (LLM) failed (500)'),
            ),
          ),
        );
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    });

    test('throws StateError on unexpected response', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        unawaited(() async {
          await for (final request in server) {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'foo': 'bar'}));
            await request.response.close();
          }
        }());

        expect(
          () => postChatCompletion(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'key',
            extraHeaders: const {},
            payload: '{}',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unexpected response'),
            ),
          ),
        );
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    });

    test('truncates long error body to 600 chars', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        unawaited(() async {
          await for (final request in server) {
            request.response.statusCode = 400;
            request.response.write('x' * 1000);
            await request.response.close();
          }
        }());

        expect(
          () => postChatCompletion(
            baseUrl: 'http://${server.address.host}:${server.port}',
            apiKey: 'key',
            extraHeaders: const {},
            payload: '{}',
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              allOf(
                contains('Cloud ASR (LLM) failed (400)'),
                contains('…'),
              ),
            ),
          ),
        );
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    });
  });
}

final class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}
