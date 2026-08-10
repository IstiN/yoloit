import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/cli_server_http.dart';
import 'package:yoloit/core/cli/handlers/voice_settings_handler.dart';

shelf.Request _request(String method, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080/api/voice-settings');
  if (body == null) return shelf.Request(method, uri);
  return shelf.Request(method, uri, body: jsonEncode(body));
}

Future<({int status, Map<String, dynamic> json})> _call(
  String method,
  List<String> sub, {
  Map<String, dynamic>? body,
}) async {
  final response = await handleVoiceSettings(
    method,
    sub,
    _request(method, body: body),
    body: cliReadJsonBody,
    json: cliJson,
    error: cliError,
    notFound: cliNotFound,
  );
  return (
    status: response.statusCode,
    json: jsonDecode(await response.readAsString()) as Map<String, dynamic>,
  );
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('handleVoiceSettings', () {
    test('GET returns the default voice settings', () async {
      final res = await _call('GET', const []);

      expect(res.status, 200);
      expect(res.json['ok'], true);
      expect(res.json['useCloudAsr'], true);
      expect(res.json['convertWavToMp3'], false);
      expect(res.json['useChatModelForCloudAsr'], true);
      expect(res.json['cloudAsrConfigId'], isNull);
      expect(res.json['cloudAsrModel'], isNull);
    });

    test('POST updates and persists voice settings', () async {
      final updated = await _call(
        'POST',
        const [],
        body: const {
          'convertWavToMp3': true,
          'useChatModelForCloudAsr': false,
          'cloudAsrConfigId': 'cfg-1',
          'cloudAsrModel': 'whisper-large',
        },
      );

      expect(updated.status, 200);
      expect(updated.json['ok'], true);
      expect(updated.json['useCloudAsr'], true);
      expect(updated.json['convertWavToMp3'], true);
      expect(updated.json['useChatModelForCloudAsr'], false);
      expect(updated.json['cloudAsrConfigId'], 'cfg-1');
      expect(updated.json['cloudAsrModel'], 'whisper-large');

      final fetched = await _call('GET', const []);
      expect(fetched.json['convertWavToMp3'], true);
      expect(fetched.json['useChatModelForCloudAsr'], false);
      expect(fetched.json['cloudAsrConfigId'], 'cfg-1');
      expect(fetched.json['cloudAsrModel'], 'whisper-large');
    });

    test('POST with an empty body keeps the current values', () async {
      await _call('POST', const [], body: const {'cloudAsrModel': 'base'});

      final res = await _call('POST', const [], body: const {});

      expect(res.status, 200);
      expect(res.json['cloudAsrModel'], 'base');
      expect(res.json['useCloudAsr'], true);
      expect(res.json['convertWavToMp3'], false);
    });

    test('POST clears nullable fields when explicitly set to null', () async {
      await _call('POST', const [], body: const {'cloudAsrConfigId': 'cfg-1'});

      final res = await _call(
        'POST',
        const [],
        body: const <String, dynamic>{'cloudAsrConfigId': null},
      );

      expect(res.status, 200);
      expect(res.json['cloudAsrConfigId'], isNull);
    });

    test('returns 404 for unknown sub-routes', () async {
      final res = await _call('GET', const ['extra']);

      expect(res.status, 404);
      expect(res.json['error'], contains('Unknown voice-settings route'));
    });

    test('returns 404 for unsupported methods', () async {
      final res = await _call('DELETE', const []);

      expect(res.status, 404);
      expect(res.json['error'], contains('Unknown voice-settings route'));
    });
  });
}
