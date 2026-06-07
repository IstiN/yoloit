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

  // GET /api/cloud-providers → list all configs + active id + provider type
  if (sub.isEmpty && method == 'GET') {
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

  Future<shelf.Response> withId(
    Future<shelf.Response> Function(String id, Map<String, dynamic> body) action,
  ) async {
    final requestBody = await body(request);
    final id = requestBody['id'] as String?;
    if (id == null || id.trim().isEmpty) {
      return error(missingField('id'));
    }
    return action(id, requestBody);
  }

  // POST /api/cloud-providers/add { name, baseUrl, apiKey, model, extraHeaders? }
  if (sub.length == 1 && sub[0] == 'add' && method == 'POST') {
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
  if (sub.length == 1 && sub[0] == 'remove' && method == 'POST') {
    return withId((id, _) async {
      await effectiveService.removeConfig(id);
      return json(okJson({'action': 'remove', 'id': id}));
    });
  }

  // POST /api/cloud-providers/select { id }
  if (sub.length == 1 && sub[0] == 'select' && method == 'POST') {
    return withId((id, _) async {
      await effectiveService.saveActiveConfigId(id);
      return json(okJson({'action': 'select', 'id': id}));
    });
  }

  // POST /api/cloud-providers/provider-type { type: 'local'|'cloud' }
  if (sub.length == 1 && sub[0] == 'provider-type' && method == 'POST') {
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
  if (sub.length == 1 && sub[0] == 'update' && method == 'POST') {
    return withId((id, requestBody) async {
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

  return notFound(unknownRoute('cloud-providers'));
}
