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

  Future<shelf.Response> runModelAction(
    String action,
    Future<void> Function(String modelId) execute, {
    String? alias,
  }) async {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error(missingField('id'));
    }
    await execute(modelId);
    return json(
      okJson({'action': action, 'id': modelId, if (alias != null) 'alias': alias}),
    );
  }

  if (sub.length == 1 && sub[0] == 'download' && method == 'POST') {
    return runModelAction(
      'download',
      localService.downloadOrUpdateModel,
    );
  }
  if (sub.length == 1 && sub[0] == 'resume' && method == 'POST') {
    return runModelAction(
      'resume',
      localService.resumeModelDownload,
    );
  }
  if (sub.length == 1 && sub[0] == 'stop' && method == 'POST') {
    return runModelAction(
      'pause',
      localService.pauseModelDownload,
      alias: 'stop',
    );
  }
  if (sub.length == 1 && sub[0] == 'pause' && method == 'POST') {
    return runModelAction(
      'pause',
      localService.pauseModelDownload,
    );
  }
  if (sub.length == 1 && sub[0] == 'cancel' && method == 'POST') {
    return runModelAction(
      'cancel',
      localService.cancelModelDownload,
    );
  }
  if (sub.length == 1 && sub[0] == 'delete' && method == 'POST') {
    return runModelAction(
      'delete',
      localService.deleteInstalledModel,
    );
  }
  if (sub.length == 1 && sub[0] == 'select' && method == 'POST') {
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

  return notFound(unknownRoute('local-models'));
}
