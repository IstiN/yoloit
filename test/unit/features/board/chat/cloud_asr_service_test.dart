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

  group('CloudAsrService._prepareTranscriptionUpload', () {
    late Directory tmp;
    late CloudAsrService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cloud_asr_prep');
      service = CloudAsrService(settingsService: _FakeSettings());
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    test('returns the wav path unchanged when conversion is disabled',
        () async {
      final wav = File('${tmp.path}/take.wav')
        ..writeAsBytesSync(const [1, 2, 3]);

      final (path, mime) = await service.prepareTranscriptionUploadForTest(
        audioPath: wav.path,
        convertToMp3: false,
      );

      expect(path, wav.path);
      expect(mime, 'audio/wav');
    });

    test('falls back to the wav when ffmpeg cannot convert the file',
        () async {
      // Garbage content makes ffmpeg exit non-zero (or it is absent
      // entirely) — either way the original wav must be kept.
      final wav = File('${tmp.path}/broken.wav')
        ..writeAsBytesSync(const [0, 255, 13]);

      final (path, mime) = await service.prepareTranscriptionUploadForTest(
        audioPath: wav.path,
        convertToMp3: true,
      );

      expect(path, wav.path);
      expect(mime, 'audio/wav');
    });

    test('throws when the audio file does not exist', () {
      expect(
        () => service.prepareTranscriptionUploadForTest(
          audioPath: '${tmp.path}/missing.wav',
          convertToMp3: false,
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Recorded audio file not found'),
          ),
        ),
      );
    });
  });

  group('CloudAsrService.transcribeFromFile', () {
    late Directory tmp;
    late _FakeSettings settings;
    late CloudAsrService service;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('cloud_asr_file');
      settings = _FakeSettings();
      service = CloudAsrService(settingsService: settings);
    });

    tearDown(() {
      if (tmp.existsSync()) {
        tmp.deleteSync(recursive: true);
      }
    });

    test('chat mode reads the file and posts inline wav audio', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        String? seenPath;
        String? seenBody;
        unawaited(() async {
          await for (final request in server) {
            seenPath = request.uri.path;
            seenBody = await utf8.decoder.bind(request).join();
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': '  file transcript  '},
                  },
                ],
              }),
            );
            await request.response.close();
          }
        }());

        final wav = File('${tmp.path}/voice.wav')
          ..writeAsBytesSync(const [10, 20, 30]);
        settings.active = _config(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );

        final result = await service.transcribeFromFile(
          audioPath: wav.path,
          voiceSettings: const VoiceSettings(useChatModelForCloudAsr: true),
        );

        expect(result, 'file transcript');
        expect(seenPath, '/chat/completions');
        expect(seenBody, contains(base64Encode(const [10, 20, 30])));
        expect(seenBody, contains('"wav"'));
        // No mp3 conversion requested → no temp file cleanup needed.
        expect(File('${tmp.path}/voice.mp3').existsSync(), isFalse);
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('dedicated mode uploads the file as multipart form data', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        String? seenPath;
        String? seenContentType;
        String? seenBody;
        unawaited(() async {
          await for (final request in server) {
            seenPath = request.uri.path;
            seenContentType = request.headers.contentType?.toString();
            seenBody = await utf8.decoder.bind(request).join();
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({'text': 'cloud file'}));
            await request.response.close();
          }
        }());

        final wav = File('${tmp.path}/meeting.wav')
          ..writeAsBytesSync(const [7, 7, 7]);
        settings.active = _config(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );

        final result = await service.transcribeFromFile(
          audioPath: wav.path,
          voiceSettings: const VoiceSettings(useChatModelForCloudAsr: false),
        );

        expect(result, 'cloud file');
        expect(seenPath, '/audio/transcriptions');
        expect(seenContentType, contains('multipart/form-data'));
        expect(seenBody, contains('filename="meeting.wav"'));
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('failed mp3 conversion keeps the original wav upload', () async {
      await HttpOverrides.runZoned(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(server.close);

        String? seenBody;
        unawaited(() async {
          await for (final request in server) {
            seenBody = await utf8.decoder.bind(request).join();
            request.response.headers.contentType = ContentType.json;
            request.response.write(
              jsonEncode({
                'choices': [
                  {
                    'message': {'content': 'fallback wav'},
                  },
                ],
              }),
            );
            await request.response.close();
          }
        }());

        final wav = File('${tmp.path}/corrupt.wav')
          ..writeAsBytesSync(const [0, 255, 13]);
        settings.active = _config(
          baseUrl: 'http://${server.address.host}:${server.port}',
        );

        final result = await service.transcribeFromFile(
          audioPath: wav.path,
          voiceSettings: const VoiceSettings(
            useChatModelForCloudAsr: true,
            convertWavToMp3: true,
          ),
        );

        expect(result, 'fallback wav');
        // ffmpeg could not convert the garbage bytes → wav format kept.
        expect(seenBody, contains('"wav"'));
        expect(seenBody, contains(base64Encode(const [0, 255, 13])));
      }, createHttpClient: _PassthroughHttpOverrides().createHttpClient);
    }, timeout: const Timeout(Duration(seconds: 15)));

    test('throws when the recorded audio file is missing', () {
      settings.active = _config();

      expect(
        () => service.transcribeFromFile(
          audioPath: '${tmp.path}/gone.wav',
          voiceSettings: const VoiceSettings(),
        ),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Recorded audio file not found'),
          ),
        ),
      );
    });
  });
}

final class _PassthroughHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      super.createHttpClient(context);
}
