import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/cloud_providers_handler.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

class _MockCloudLlmSettingsService extends Mock
    implements CloudLlmSettingsService {}

shelf.Request _getRequest(String path) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request('GET', uri);
}

shelf.Request _postRequest(String path, {Map<String, dynamic>? body}) {
  final uri = Uri.parse('http://localhost:8080$path');
  return shelf.Request(
    'POST',
    uri,
    body: body != null ? jsonEncode(body) : null,
  );
}

shelf.Response _json(Object data) => shelf.Response.ok(
  jsonEncode(data),
  headers: {'content-type': 'application/json'},
);

shelf.Response _error(String msg) => shelf.Response(
  400,
  body: jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

shelf.Response _notFound(String msg) => shelf.Response.notFound(
  jsonEncode({'ok': false, 'error': msg}),
  headers: {'content-type': 'application/json'},
);

Future<Map<String, dynamic>> _body(shelf.Request request) async {
  final raw = await request.readAsString();
  if (raw.isEmpty) return {};
  return jsonDecode(raw) as Map<String, dynamic>;
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const CloudLlmConfig(
        id: '',
        name: '',
        baseUrl: '',
        apiKey: '',
        model: '',
      ),
    );
  });

  group('handleCloudProviders', () {
    late _MockCloudLlmSettingsService mockService;

    setUp(() {
      mockService = _MockCloudLlmSettingsService();

      when(() => mockService.loadConfigs()).thenAnswer((_) async => []);
      when(() => mockService.loadActiveConfigId()).thenAnswer((_) async => null);
      when(() => mockService.loadAssistantProviderType())
          .thenAnswer((_) async => 'local');
      when(() => mockService.upsertConfig(any())).thenAnswer((_) async {});
      when(() => mockService.removeConfig(any())).thenAnswer((_) async {});
      when(() => mockService.saveActiveConfigId(any())).thenAnswer((_) async {});
      when(() => mockService.saveAssistantProviderType(any()))
          .thenAnswer((_) async {});
    });

    test('GET /cloud-providers returns empty list', () async {
      final response = await handleCloudProviders(
        'GET',
        [],
        _getRequest('/api/cloud-providers'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['providerType'], 'local');
      expect(body['activeConfigId'], isNull);
      expect((body['configs'] as List).isEmpty, true);
    });

    test('POST /cloud-providers/add creates config', () async {
      final response = await handleCloudProviders(
        'POST',
        ['add'],
        _postRequest('/api/cloud-providers/add', body: {
          'name': 'OpenRouter',
          'baseUrl': 'https://openrouter.ai/api/v1',
          'apiKey': 'sk-test',
          'model': 'gpt-4',
        }),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['action'], 'add');
      verify(() => mockService.upsertConfig(any())).called(1);
    });

    test('POST /cloud-providers/add missing fields returns error', () async {
      final response = await handleCloudProviders(
        'POST',
        ['add'],
        _postRequest('/api/cloud-providers/add', body: {'name': 'OpenRouter'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /cloud-providers/remove removes config', () async {
      final response = await handleCloudProviders(
        'POST',
        ['remove'],
        _postRequest('/api/cloud-providers/remove', body: {'id': 'cfg-1'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['action'], 'remove');
      verify(() => mockService.removeConfig('cfg-1')).called(1);
    });

    test('POST /cloud-providers/remove missing id returns error', () async {
      final response = await handleCloudProviders(
        'POST',
        ['remove'],
        _postRequest('/api/cloud-providers/remove'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /cloud-providers/select sets active config', () async {
      final response = await handleCloudProviders(
        'POST',
        ['select'],
        _postRequest('/api/cloud-providers/select', body: {'id': 'cfg-1'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['action'], 'select');
      verify(() => mockService.saveActiveConfigId('cfg-1')).called(1);
    });

    test('POST /cloud-providers/provider-type sets type', () async {
      final response = await handleCloudProviders(
        'POST',
        ['provider-type'],
        _postRequest('/api/cloud-providers/provider-type', body: {'type': 'cloud'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['type'], 'cloud');
      verify(() => mockService.saveAssistantProviderType('cloud')).called(1);
    });

    test('POST /cloud-providers/provider-type invalid type returns error',
        () async {
      final response = await handleCloudProviders(
        'POST',
        ['provider-type'],
        _postRequest('/api/cloud-providers/provider-type', body: {'type': 'invalid'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /cloud-providers/provider-type missing type returns error',
        () async {
      final response = await handleCloudProviders(
        'POST',
        ['provider-type'],
        _postRequest('/api/cloud-providers/provider-type'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /cloud-providers/update updates config', () async {
      when(() => mockService.loadConfigById('cfg-1')).thenAnswer(
        (_) async => const CloudLlmConfig(
          id: 'cfg-1',
          name: 'Old',
          baseUrl: 'http://old',
          apiKey: 'old',
          model: 'old',
        ),
      );

      final response = await handleCloudProviders(
        'POST',
        ['update'],
        _postRequest('/api/cloud-providers/update', body: {
          'id': 'cfg-1',
          'name': 'New',
        }),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], true);
      expect(body['action'], 'update');
      verify(() => mockService.upsertConfig(any())).called(1);
    });

    test('POST /cloud-providers/update unknown config returns error', () async {
      when(() => mockService.loadConfigById('unknown'))
          .thenAnswer((_) async => null);

      final response = await handleCloudProviders(
        'POST',
        ['update'],
        _postRequest('/api/cloud-providers/update', body: {
          'id': 'unknown',
          'name': 'New',
        }),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('POST /cloud-providers/update missing id returns error', () async {
      final response = await handleCloudProviders(
        'POST',
        ['update'],
        _postRequest('/api/cloud-providers/update', body: {'name': 'New'}),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 400);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      expect(body['ok'], false);
    });

    test('unknown route returns notFound', () async {
      final response = await handleCloudProviders(
        'GET',
        ['unknown'],
        _getRequest('/api/cloud-providers/unknown'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 404);
    });

    test('GET /cloud-providers returns configs with hasKey flag', () async {
      when(() => mockService.loadConfigs()).thenAnswer(
        (_) async => [
          const CloudLlmConfig(
            id: 'cfg-1',
            name: 'Test',
            baseUrl: 'http://test',
            apiKey: 'secret',
            model: 'gpt-4',
          ),
          const CloudLlmConfig(
            id: 'cfg-2',
            name: 'Empty',
            baseUrl: 'http://empty',
            apiKey: '',
            model: 'gpt-3',
          ),
        ],
      );
      when(() => mockService.loadActiveConfigId())
          .thenAnswer((_) async => 'cfg-1');

      final response = await handleCloudProviders(
        'GET',
        [],
        _getRequest('/api/cloud-providers'),
        body: _body,
        json: _json,
        error: _error,
        notFound: _notFound,
        service: mockService,
      );

      expect(response.statusCode, 200);
      final body = jsonDecode(await response.readAsString()) as Map<String, dynamic>;
      final configs = body['configs'] as List;
      expect(configs.length, 2);
      expect(configs[0]['hasKey'], true);
      expect(configs[1]['hasKey'], false);
      expect(configs[0]['apiKey'], isNull);
    });
  });
}
