import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/cli/handlers/server_helpers.dart';
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

Future<shelf.Response> handleLocalModels(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
  LocalAiModelsService? service,
}) async {
  final localService = service ?? LocalAiModelsService.instance;
  await localService.initialize();

  if (sub.isEmpty && method == 'GET') {
    return json(localService.snapshot());
  }

  if (method == 'POST' && sub.length == 1) {
    return _handleModelAction(
      sub[0],
      localService,
      request,
      body: body,
      json: json,
      error: error,
      notFound: notFound,
    );
  }

  return notFound(unknownRoute('local-models'));
}

/// A single-segment model action: the response `action` label, the service
/// method to execute, and an optional response `alias`.
typedef _ModelActionRoute = ({
  String action,
  Future<void> Function(String modelId) execute,
  String? alias,
});

Map<String, _ModelActionRoute> _modelActionRoutes(
  LocalAiModelsService localService,
) => {
  'download': (
    action: 'download',
    execute: localService.downloadOrUpdateModel,
    alias: null,
  ),
  'resume': (
    action: 'resume',
    execute: localService.resumeModelDownload,
    alias: null,
  ),
  'stop': (
    action: 'pause',
    execute: localService.pauseModelDownload,
    alias: 'stop',
  ),
  'pause': (
    action: 'pause',
    execute: localService.pauseModelDownload,
    alias: null,
  ),
  'cancel': (
    action: 'cancel',
    execute: localService.cancelModelDownload,
    alias: null,
  ),
  'delete': (
    action: 'delete',
    execute: localService.deleteInstalledModel,
    alias: null,
  ),
};

Future<shelf.Response> _handleModelAction(
  String name,
  LocalAiModelsService localService,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  if (name == 'select') {
    return _selectModel(
      localService,
      request,
      body: body,
      json: json,
      error: error,
    );
  }
  final route = _modelActionRoutes(localService)[name];
  if (route == null) return notFound(unknownRoute('local-models'));
  return _runModelAction(
    route.action,
    route.execute,
    request,
    body: body,
    json: json,
    error: error,
    alias: route.alias,
  );
}

Future<shelf.Response> _runModelAction(
  String action,
  Future<void> Function(String modelId) execute,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  String? alias,
}) async {
  final requestBody = await body(request);
  final modelId = requestBody['id'] as String?;
  if (modelId == null || modelId.trim().isEmpty) {
    return error(missingField('id'));
  }
  await execute(modelId);
  return json(
    okJson({
      'action': action,
      'id': modelId,
      if (alias != null) 'alias': alias,
    }),
  );
}

Future<shelf.Response> _selectModel(
  LocalAiModelsService localService,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
}) async {
  final requestBody = await body(request);
  final kind = requestBody['kind'] as String?;
  final modelId = requestBody['id'] as String?;
  if (kind == null || modelId == null) {
    return error(missingFields(const ['kind', 'id']));
  }
  if (kind == 'chat') {
    await localService.setSelectedChatModel(modelId);
  } else if (kind == 'asr') {
    await localService.setSelectedAsrModel(modelId);
  } else {
    return error('Unsupported kind "$kind". Expected "chat" or "asr".');
  }
  return json(okJson({'action': 'select', 'kind': kind, 'id': modelId}));
}
