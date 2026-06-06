import 'dart:async';

import 'package:local_models_flutter/local_models_flutter.dart' as flm;
import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/features/settings/data/local_ai_models_service.dart';

Future<shelf.Response> handleLmGenerate(
  shelf.Request request, {
  required Future<Map<String, dynamic>> Function(shelf.Request) body,
  required shelf.Response Function(Object) json,
  required shelf.Response Function(String) error,
}) async {
  final requestBody = await body(request);
  final service = LocalAiModelsService.instance;
  final modelId = requestBody['modelId'] as String? ?? service.selectedChatModelId;
  final systemPrompt = requestBody['systemPrompt'] as String? ?? '';
  final rawMessages = requestBody['messages'] as List<dynamic>? ?? [];
  final maxTokens = (requestBody['maxTokens'] as num?)?.toInt() ?? 512;
  final temperature = (requestBody['temperature'] as num?)?.toDouble() ?? 0.2;
  // enableThinking: explicit bool from body, or auto-false for Qwen3 models
  final bool? enableThinking =
      requestBody.containsKey('enableThinking')
          ? (requestBody['enableThinking'] as bool?)
          : (modelId.toLowerCase().contains('qwen3') ? false : null);

  await service.initialize();
  await service.ensureRuntimeReady();
  final installedInfo = service.installedModelById(modelId);
  if (installedInfo == null) {
    return error('Model "$modelId" is not installed');
  }

  final messages = <Map<String, String>>[];
  if (systemPrompt.isNotEmpty) {
    messages.add({'role': 'system', 'content': systemPrompt});
  }
  for (final m in rawMessages) {
    if (m is Map) {
      messages.add({
        'role': m['role'] as String? ?? 'user',
        'content': m['content'] as String? ?? '',
      });
    }
  }
  if (messages.isEmpty || messages.last['role'] != 'user') {
    return error('At least one user message is required');
  }

  try {
    final engine = flm.NativeLmEngine();
    final installed = flm.InstalledModel(
      manifest: installedInfo.manifest,
      directory: installedInfo.directory,
      sourceLabel: installedInfo.sourceLabel,
      installedAt: installedInfo.installedAt,
      sizeBytes: installedInfo.sizeBytes,
      metadataUpdatedAt: installedInfo.metadataUpdatedAt,
    );
    final t0 = DateTime.now();
    int firstTokenMs = -1;
    final buffer = StringBuffer();
    int tokenCount = 0;

    final full = await engine.completeStreaming(
      flm.LmCompletionRequest(
        modelPath: installed.directory.path,
        manifest: installed.manifest,
        messages: messages,
        maxTokens: maxTokens,
        temperature: temperature,
        enableThinking: enableThinking,
        tools: [],
      ),
      (chunk) {
        if (firstTokenMs < 0) {
          firstTokenMs = DateTime.now().difference(t0).inMilliseconds;
        }
        buffer.write(chunk);
        tokenCount++;
      },
    );

    final totalMs = DateTime.now().difference(t0).inMilliseconds;
    final genMs = totalMs - (firstTokenMs < 0 ? 0 : firstTokenMs);
    final response =
        full.trim().isNotEmpty ? full.trim() : buffer.toString().trim();
    final hasThink = response.contains('<think>');

    return json({
      'ok': true,
      'modelId': modelId,
      'response': response,
      'hasThinkBlock': hasThink,
      'timings': {
        'ttftMs': firstTokenMs,
        'generationMs': genMs,
        'totalMs': totalMs,
        'tokens': tokenCount,
        'tps': genMs > 0 ? (tokenCount * 1000.0 / genMs).roundToDouble() : 0,
      },
    });
  } catch (e) {
    return error('LM generate error: $e');
  }
}
