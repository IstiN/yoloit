import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

Future<shelf.Response> handleLocalModels(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  final service = LocalAiModelsService.instance;
  await service.initialize();

  if (sub.isEmpty && method == 'GET') {
    return json(service.snapshot());
  }
  if (sub.length == 1 && sub[0] == 'download' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.downloadOrUpdateModel(modelId);
    return json({'ok': true, 'action': 'download', 'id': modelId});
  }
  if (sub.length == 1 && sub[0] == 'resume' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.resumeModelDownload(modelId);
    return json({'ok': true, 'action': 'resume', 'id': modelId});
  }
  if (sub.length == 1 && sub[0] == 'stop' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.pauseModelDownload(modelId);
    return json({
      'ok': true,
      'action': 'pause',
      'id': modelId,
      'alias': 'stop',
    });
  }
  if (sub.length == 1 && sub[0] == 'pause' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.pauseModelDownload(modelId);
    return json({'ok': true, 'action': 'pause', 'id': modelId});
  }
  if (sub.length == 1 && sub[0] == 'cancel' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.cancelModelDownload(modelId);
    return json({'ok': true, 'action': 'cancel', 'id': modelId});
  }
  if (sub.length == 1 && sub[0] == 'delete' && method == 'POST') {
    final requestBody = await body(request);
    final modelId = requestBody['id'] as String?;
    if (modelId == null || modelId.trim().isEmpty) {
      return error('Missing "id" field');
    }
    await service.deleteInstalledModel(modelId);
    return json({'ok': true, 'action': 'delete', 'id': modelId});
  }
  if (sub.length == 1 && sub[0] == 'select' && method == 'POST') {
    final requestBody = await body(request);
    final kind = requestBody['kind'] as String?;
    final modelId = requestBody['id'] as String?;
    if (kind == null || modelId == null) {
      return error('Missing "kind" or "id" field');
    }
    if (kind == 'chat') {
      await service.setSelectedChatModel(modelId);
    } else if (kind == 'asr') {
      await service.setSelectedAsrModel(modelId);
    } else {
      return error('Unsupported kind "$kind". Expected "chat" or "asr".');
    }
    return json({
      'ok': true,
      'action': 'select',
      'kind': kind,
      'id': modelId,
    });
  }

  return notFound('Unknown local-models route');
}
