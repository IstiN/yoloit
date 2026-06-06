import 'dart:async';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

Future<shelf.Response> handleVoiceSettings(
  String method,
  List<String> sub,
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
  required shelf.Response Function(String) notFound,
}) async {
  final service = CloudLlmSettingsService.instance;

  // GET /api/voice-settings → current voice settings
  if (sub.isEmpty && method == 'GET') {
    final settings = await service.loadVoiceSettings();
    return json({
      'ok': true,
      'useCloudAsr': settings.useCloudAsr,
      'convertWavToMp3': settings.convertWavToMp3,
      'useChatModelForCloudAsr': settings.useChatModelForCloudAsr,
      'cloudAsrConfigId': settings.cloudAsrConfigId,
      'cloudAsrModel': settings.cloudAsrModel,
    });
  }

  // POST /api/voice-settings { useCloudAsr?, convertWavToMp3?, cloudAsrConfigId?, cloudAsrModel? }
  if (sub.isEmpty && method == 'POST') {
    final requestBody = await body(request);
    final current = await service.loadVoiceSettings();
    final updated = current.copyWith(
      useCloudAsr: requestBody['useCloudAsr'] as bool? ?? current.useCloudAsr,
      convertWavToMp3:
          requestBody['convertWavToMp3'] as bool? ?? current.convertWavToMp3,
      useChatModelForCloudAsr:
          requestBody['useChatModelForCloudAsr'] as bool? ??
          current.useChatModelForCloudAsr,
      cloudAsrConfigId:
          requestBody.containsKey('cloudAsrConfigId')
              ? requestBody['cloudAsrConfigId'] as String?
              : current.cloudAsrConfigId,
      cloudAsrModel:
          requestBody.containsKey('cloudAsrModel')
              ? requestBody['cloudAsrModel'] as String?
              : current.cloudAsrModel,
    );
    await service.saveVoiceSettings(updated);
    return json({
      'ok': true,
      'useCloudAsr': updated.useCloudAsr,
      'convertWavToMp3': updated.convertWavToMp3,
      'useChatModelForCloudAsr': updated.useChatModelForCloudAsr,
      'cloudAsrConfigId': updated.cloudAsrConfigId,
      'cloudAsrModel': updated.cloudAsrModel,
    });
  }

  return notFound('Unknown voice-settings route');
}
