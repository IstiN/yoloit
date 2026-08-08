import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/chat/cloud_asr_service.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

/// Settings fake that only implements the two reads
/// [CloudAsrService] actually performs.
class _FakeSettings extends Fake implements CloudLlmSettingsService {
  CloudLlmConfig? byId;
  CloudLlmConfig? active;
  String? requestedId;

  @override
  Future<CloudLlmConfig?> loadConfigById(String id) async {
    requestedId = id;
    return byId;
  }

  @override
  Future<CloudLlmConfig?> loadActiveConfig() async => active;
}

CloudLlmConfig _config({
  String id = 'cfg',
  String baseUrl = 'http://127.0.0.1:1',
  String apiKey = 'key',
  String model = 'base-model',
}) {
  return CloudLlmConfig(
    id: id,
    name: id,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
  );
}

void main() {
  group('CloudAsrService._resolveConfigAndModel', () {
    late _FakeSettings settings;
    late CloudAsrService service;

    setUp(() {
      settings = _FakeSettings();
      service = CloudAsrService(settingsService: settings);
    });

    test('throws when no cloud config exists', () {
      expect(
        () => service.transcribeFromBytes(
          audioBytes: Uint8List.fromList(const [1, 2, 3]),
          voiceSettings: const VoiceSettings(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test('throws when the resolved config is invalid', () {
      settings.active = _config(baseUrl: '', apiKey: '');

      expect(
        () => service.transcribeFromBytes(
          audioBytes: Uint8List.fromList(const [1]),
          voiceSettings: const VoiceSettings(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('not configured'),
          ),
        ),
      );
    });

    test(
      'chat mode ignores cloudAsrConfigId and uses the active config',
      () async {
        await HttpOverrides.runZoned(() async {
          final server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(server.close);

          String? seenPath;
          unawaited(() async {
            await for (final request in server) {
              seenPath = request.uri.path;
              await request.drain<void>();
              request.response.headers.contentType = ContentType.json;
              request.response.write(
                jsonEncode({
                  'choices': [
                    {
                      'message': {'content': '  chat transcript  '},
                    },
                  ],
                }),
              );
              await request.response.close();
            }
          }());

          settings.active = _config(
            baseUrl: 'http://${server.address.host}:${server.port}',
          );

          final result = await service.transcribeFromBytes(
            audioBytes: Uint8List.fromList(const [1, 2, 3]),
            voiceSettings: const VoiceSettings(
              useChatModelForCloudAsr: true,
              cloudAsrConfigId: 'must-not-be-loaded',
            ),
          );

          expect(result, 'chat transcript');
          expect(seenPath, '/chat/completions');
          // Explicit config id is ignored in chat mode.
          expect(settings.requestedId, isNull);
        }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'dedicated mode loads the trimmed explicit config id and '
      'prefers cloudAsrModel',
      () async {
        await HttpOverrides.runZoned(() async {
          final server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(server.close);

          String? seenPath;
          String? seenModel;
          unawaited(() async {
            await for (final request in server) {
              seenPath = request.uri.path;
              final body = await utf8.decoder.bind(request).join();
              final decoded = jsonDecode(body) as Map<String, dynamic>;
              seenModel = decoded['model'] as String?;
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode({'text': 'cloud transcript'}));
              await request.response.close();
            }
          }());

          settings.byId = _config(
            id: 'cfg-1',
            baseUrl: 'http://${server.address.host}:${server.port}',
            model: 'config-model',
          );

          final result = await service.transcribeFromBytes(
            audioBytes: Uint8List.fromList(const [9, 9]),
            voiceSettings: const VoiceSettings(
              useChatModelForCloudAsr: false,
              cloudAsrConfigId: '  cfg-1  ',
              cloudAsrModel: 'custom-asr-model',
            ),
          );

          expect(result, 'cloud transcript');
          expect(seenPath, '/audio/transcriptions');
          expect(settings.requestedId, 'cfg-1');
          expect(seenModel, 'custom-asr-model');
        }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'falls back to the active config when the explicit id is missing',
      () async {
        await HttpOverrides.runZoned(() async {
          final server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(server.close);

          String? seenModel;
          unawaited(() async {
            await for (final request in server) {
              final body = await utf8.decoder.bind(request).join();
              seenModel =
                  (jsonDecode(body) as Map<String, dynamic>)['model']
                      as String?;
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode({'text': 'ok'}));
              await request.response.close();
            }
          }());

          settings.byId = null;
          settings.active = _config(
            baseUrl: 'http://${server.address.host}:${server.port}',
            model: 'active-model',
          );

          final result = await service.transcribeFromBytes(
            audioBytes: Uint8List.fromList(const [5]),
            voiceSettings: const VoiceSettings(
              useChatModelForCloudAsr: false,
              cloudAsrConfigId: 'missing-id',
            ),
          );

          expect(result, 'ok');
          expect(settings.requestedId, 'missing-id');
          expect(seenModel, 'active-model');
        }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );

    test(
      'blank cloudAsrModel falls back to the config model',
      () async {
        await HttpOverrides.runZoned(() async {
          final server = await HttpServer.bind(
            InternetAddress.loopbackIPv4,
            0,
          );
          addTearDown(server.close);

          String? seenModel;
          unawaited(() async {
            await for (final request in server) {
              final body = await utf8.decoder.bind(request).join();
              seenModel =
                  (jsonDecode(body) as Map<String, dynamic>)['model']
                      as String?;
              request.response.headers.contentType = ContentType.json;
              request.response.write(jsonEncode({'text': 'ok'}));
              await request.response.close();
            }
          }());

          settings.active = _config(
            baseUrl: 'http://${server.address.host}:${server.port}',
            model: 'config-model',
          );

          final result = await service.transcribeFromBytes(
            audioBytes: Uint8List.fromList(const [7]),
            voiceSettings: const VoiceSettings(
              useChatModelForCloudAsr: false,
              cloudAsrModel: '   ',
            ),
          );

          expect(result, 'ok');
          expect(seenModel, 'config-model');
        }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
      },
      timeout: const Timeout(Duration(seconds: 15)),
    );
  });
}

final class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}
