import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

Future<shelf.Response> handleCloudProviders(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  CloudLlmSettingsService? service,
}) async {
  final effectiveService = service ?? CloudLlmSettingsService.instance;

  final routes = <(bool Function(), Future<shelf.Response> Function())>[
    (
      () => sub.isEmpty && method == 'GET',
      () => _listProviders(effectiveService, json),
    ),
    (
      () => sub.length == 1 && sub[0] == 'add' && method == 'POST',
      () => _addProvider(request, effectiveService, body, json, error),
    ),
    (
      () => sub.length == 1 && sub[0] == 'remove' && method == 'POST',
      () => _removeProvider(request, effectiveService, body, json, error),
    ),
    (
      () => sub.length == 1 && sub[0] == 'select' && method == 'POST',
      () => _selectProvider(request, effectiveService, body, json, error),
    ),
    (
      () => sub.length == 1 && sub[0] == 'provider-type' && method == 'POST',
      () => _setProviderType(request, effectiveService, body, json, error),
    ),
    (
      () => sub.length == 1 && sub[0] == 'update' && method == 'POST',
      () => _updateProvider(request, effectiveService, body, json, error),
    ),
  ];
  for (final (matches, run) in routes) {
    if (matches()) return run();
  }

  return notFound(unknownRoute('cloud-providers'));
}

Future<shelf.Response> _withId(
  shelf.Request request,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(String) error,
  Future<shelf.Response> Function(String id, Map<String, dynamic> body) action,
) async {
  final requestBody = await body(request);
  final id = requestBody['id'] as String?;
  if (id == null || id.trim().isEmpty) {
    return error(missingField('id'));
  }
  return action(id, requestBody);
}

// GET /api/cloud-providers → list all configs + active id + provider type
Future<shelf.Response> _listProviders(
  CloudLlmSettingsService effectiveService,
  shelf.Response Function(Object) json,
) async {
  final configs = await effectiveService.loadConfigs();
  final activeId = await effectiveService.loadActiveConfigId();
  final providerType = await effectiveService.loadAssistantProviderType();
  return json({
    'ok': true,
    'providerType': providerType,
    'activeConfigId': activeId,
    'configs':
        configs
            .map(
              (c) => {
                'id': c.id,
                'name': c.name,
                'baseUrl': c.baseUrl,
                'model': c.model,
                'hasKey': c.apiKey.isNotEmpty,
              },
            )
            .toList(),
  });
}

// POST /api/cloud-providers/add { name, baseUrl, apiKey, model, extraHeaders? }
Future<shelf.Response> _addProvider(
  shelf.Request request,
  CloudLlmSettingsService effectiveService,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
) async {
  final requestBody = await body(request);
  final name = requestBody['name'] as String?;
  final baseUrl = requestBody['baseUrl'] as String?;
  final apiKey = requestBody['apiKey'] as String?;
  final model = requestBody['model'] as String?;
  if (name == null || baseUrl == null || apiKey == null || model == null) {
    return error(missingFields(const ['name', 'baseUrl', 'apiKey', 'model']));
  }
  final extra = <String, String>{};
  if (requestBody['extraHeaders'] is Map) {
    (requestBody['extraHeaders'] as Map).forEach((k, v) {
      extra[k.toString()] = v.toString();
    });
  }
  final config = CloudLlmConfig(
    id: 'cloud-${DateTime.now().millisecondsSinceEpoch}',
    name: name,
    baseUrl: baseUrl,
    apiKey: apiKey,
    model: model,
    extraHeaders: extra,
  );
  await effectiveService.upsertConfig(config);
  return json(okJson({'action': 'add', 'id': config.id}));
}

// POST /api/cloud-providers/remove { id }
Future<shelf.Response> _removeProvider(
  shelf.Request request,
  CloudLlmSettingsService effectiveService,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
) {
  return _withId(request, body, error, (id, _) async {
    await effectiveService.removeConfig(id);
    return json(okJson({'action': 'remove', 'id': id}));
  });
}

// POST /api/cloud-providers/select { id }
Future<shelf.Response> _selectProvider(
  shelf.Request request,
  CloudLlmSettingsService effectiveService,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
) {
  return _withId(request, body, error, (id, _) async {
    await effectiveService.saveActiveConfigId(id);
    return json(okJson({'action': 'select', 'id': id}));
  });
}

// POST /api/cloud-providers/provider-type { type: 'local'|'cloud' }
Future<shelf.Response> _setProviderType(
  shelf.Request request,
  CloudLlmSettingsService effectiveService,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
) async {
  final requestBody = await body(request);
  final type = requestBody['type'] as String?;
  if (type == null || (type != 'local' && type != 'cloud')) {
    return error(
      'Missing or invalid "type" field. Expected "local" or "cloud".',
    );
  }
  await effectiveService.saveAssistantProviderType(type);
  return json(okJson({'action': 'set-provider-type', 'type': type}));
}

// POST /api/cloud-providers/update { id, ...fields }
Future<shelf.Response> _updateProvider(
  shelf.Request request,
  CloudLlmSettingsService effectiveService,
  Future<Map<String, dynamic>> Function(shelf.Request) body,
  shelf.Response Function(Object) json,
  shelf.Response Function(String) error,
) {
  return _withId(request, body, error, (id, requestBody) async {
    final existing = await effectiveService.loadConfigById(id);
    if (existing == null) return error('Config not found: $id');
    final updated = CloudLlmConfig(
      id: id,
      name: requestBody['name'] as String? ?? existing.name,
      baseUrl: requestBody['baseUrl'] as String? ?? existing.baseUrl,
      apiKey: requestBody['apiKey'] as String? ?? existing.apiKey,
      model: requestBody['model'] as String? ?? existing.model,
      extraHeaders:
          requestBody['extraHeaders'] is Map
              ? (requestBody['extraHeaders'] as Map).map(
                (k, v) => MapEntry(k.toString(), v.toString()),
              )
              : existing.extraHeaders,
    );
    await effectiveService.upsertConfig(updated);
    return json(okJson({'action': 'update', 'id': id}));
  });
}
