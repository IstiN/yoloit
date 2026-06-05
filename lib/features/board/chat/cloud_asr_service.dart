import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yoloit/features/board/chat/cloud_asr_http_client.dart';
import 'package:yoloit/features/settings/data/cloud_llm_settings_service.dart';

class CloudAsrService {
  CloudAsrService({CloudLlmSettingsService? settingsService})
    : _settingsService = settingsService ?? CloudLlmSettingsService.instance;

  final CloudLlmSettingsService _settingsService;

  static final List<_CloudAsrPayloadAdapter> _payloadAdapters = [
    const _OpenRouterCloudAsrPayloadAdapter(),
    const _MultipartCloudAsrPayloadAdapter(),
  ];

  /// Transcribes audio directly from in-memory bytes, skipping all disk I/O.
  Future<String> transcribeFromBytes({
    required Uint8List audioBytes,
    required VoiceSettings voiceSettings,
  }) async {
    final (config, model) = await _resolveConfigAndModel(voiceSettings);

    if (voiceSettings.useChatModelForCloudAsr) {
      return _transcribeViaChatEndpoint(
        config: config,
        model: model,
        audioBytes: audioBytes,
        format: 'wav',
      );
    }
    return _transcribeViaCloudEndpointFromBytes(
      config: config,
      model: model,
      audioBytes: audioBytes,
      mimeType: 'audio/wav',
    );
  }

  Future<String> transcribeFromFile({
    required String audioPath,
    required VoiceSettings voiceSettings,
  }) async {
    final (config, model) = await _resolveConfigAndModel(voiceSettings);

    final (uploadPath, mimeType) = await _prepareTranscriptionUpload(
      audioPath: audioPath,
      convertToMp3: voiceSettings.convertWavToMp3,
    );
    try {
      if (voiceSettings.useChatModelForCloudAsr) {
        return await _transcribeViaChatEndpointFromFile(
          config: config,
          model: model,
          filePath: uploadPath,
          mimeType: mimeType,
        );
      }
      return await _transcribeViaCloudEndpointFromFile(
        config: config,
        model: model,
        filePath: uploadPath,
        mimeType: mimeType,
      );
    } finally {
      if (uploadPath != audioPath && File(uploadPath).existsSync()) {
        try {
          await File(uploadPath).delete();
        } on FileSystemException {
          // ignore temp cleanup failure
        }
      }
    }
  }

  // ── Config resolution ────────────────────────────────────────────────────

  Future<(CloudLlmConfig, String)> _resolveConfigAndModel(
    VoiceSettings voiceSettings,
  ) async {
    final explicitConfigId =
        voiceSettings.useChatModelForCloudAsr
            ? null
            : voiceSettings.cloudAsrConfigId?.trim();
    CloudLlmConfig? config;
    if (explicitConfigId != null && explicitConfigId.isNotEmpty) {
      config = await _settingsService.loadConfigById(explicitConfigId);
    }
    config ??= await _settingsService.loadActiveConfig();
    if (config == null || !config.isValid) {
      throw StateError(
        'Cloud ASR is enabled but cloud provider is not configured. '
        'Open Settings → Cloud Providers.',
      );
    }

    final model =
        !voiceSettings.useChatModelForCloudAsr &&
                voiceSettings.cloudAsrModel?.trim().isNotEmpty == true
            ? voiceSettings.cloudAsrModel!.trim()
            : config.model.trim();
    if (model.isEmpty) {
      throw StateError('Cloud ASR model is empty.');
    }
    return (config, model);
  }

  // ── Chat endpoint (inline audio) ─────────────────────────────────────────

  Future<String> _transcribeViaChatEndpoint({
    required CloudLlmConfig config,
    required String model,
    required Uint8List audioBytes,
    required String format,
  }) async {
    final payload = buildChatAudioPayload(
      model: model,
      audioBytes: audioBytes,
      format: format,
    );
    return postChatCompletion(
      baseUrl: config.baseUrl,
      apiKey: config.apiKey,
      extraHeaders: config.extraHeaders,
      payload: payload,
    );
  }

  Future<String> _transcribeViaChatEndpointFromFile({
    required CloudLlmConfig config,
    required String model,
    required String filePath,
    required String mimeType,
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    final format = mimeType == 'audio/mpeg' ? 'mp3' : 'wav';
    return _transcribeViaChatEndpoint(
      config: config,
      model: model,
      audioBytes: fileBytes,
      format: format,
    );
  }

  // ── Cloud endpoint (dedicated /audio/transcriptions) ─────────────────────

  Future<String> _transcribeViaCloudEndpointFromBytes({
    required CloudLlmConfig config,
    required String model,
    required Uint8List audioBytes,
    required String mimeType,
  }) async {
    return _performCloudTranscription(
      config: config,
      model: model,
      mimeType: mimeType,
      writeBody: (request) async {
        request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
        final payload = jsonEncode({
          'model': model,
          'input_audio': {
            'data': base64Encode(audioBytes),
            'format': mimeType == 'audio/mpeg' ? 'mp3' : 'wav',
          },
        });
        request.add(utf8.encode(payload));
      },
    );
  }

  Future<String> _transcribeViaCloudEndpointFromFile({
    required CloudLlmConfig config,
    required String model,
    required String filePath,
    required String mimeType,
  }) async {
    final fileBytes = await File(filePath).readAsBytes();
    final fileName = filePath.split(Platform.pathSeparator).last;
    return _performCloudTranscription(
      config: config,
      model: model,
      mimeType: mimeType,
      writeBody: (request) async {
        final adapter = _payloadAdapters.firstWhere(
          (candidate) => candidate.supports(
            config: config,
            baseUrl: _normalizedBaseUrl(config.baseUrl),
          ),
        );
        await adapter.writeRequest(
          request: request,
          model: model,
          fileBytes: fileBytes,
          fileName: fileName,
          mimeType: mimeType,
        );
      },
    );
  }

  Future<String> _performCloudTranscription({
    required CloudLlmConfig config,
    required String model,
    required String mimeType,
    required Future<void> Function(HttpClientRequest request) writeBody,
  }) async {
    final normalizedBase = _normalizedBaseUrl(config.baseUrl);
    final uri = Uri.parse('$normalizedBase/audio/transcriptions');
    final client = HttpClient();
    try {
      final request = await client.postUrl(uri);
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer ${config.apiKey}',
      );
      for (final entry in config.extraHeaders.entries) {
        request.headers.set(entry.key, entry.value);
      }
      await writeBody(request);
      final response = await request.close();
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
          'Cloud ASR failed (${response.statusCode}): '
          '${body.length > 600 ? '${body.substring(0, 600)}…' : body}',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text =
            (decoded['text'] as String?) ??
            (decoded['transcript'] as String?) ??
            (decoded['output_text'] as String?);
        if (text != null) return text.trim();
      }
      throw StateError('Cloud ASR returned unexpected response: $body');
    } finally {
      client.close(force: true);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  static String _normalizedBaseUrl(String baseUrl) {
    return baseUrl.replaceFirst(RegExp(r'/+$'), '');
  }

  Future<(String, String)> _prepareTranscriptionUpload({
    required String audioPath,
    required bool convertToMp3,
  }) async {
    String filePath = audioPath;
    var mimeType = 'audio/wav';

    if (convertToMp3) {
      final mp3Path = audioPath.replaceAll('.wav', '.mp3');
      try {
        final result = await Process.run('ffmpeg', [
          '-i',
          audioPath,
          '-codec:a',
          'libmp3lame',
          '-qscale:a',
          '4',
          '-y',
          mp3Path,
        ]);
        if (result.exitCode == 0 && File(mp3Path).existsSync()) {
          filePath = mp3Path;
          mimeType = 'audio/mpeg';
        }
      } on ProcessException {
        // keep original WAV when ffmpeg is unavailable
      }
    }

    if (!File(filePath).existsSync()) {
      throw StateError('Recorded audio file not found: $filePath');
    }
    return (filePath, mimeType);
  }
}

// ── Payload adapters ───────────────────────────────────────────────────────

abstract class _CloudAsrPayloadAdapter {
  const _CloudAsrPayloadAdapter();

  bool supports({required CloudLlmConfig config, required String baseUrl});

  Future<void> writeRequest({
    required HttpClientRequest request,
    required String model,
    required List<int> fileBytes,
    required String fileName,
    required String mimeType,
  });
}

class _OpenRouterCloudAsrPayloadAdapter extends _CloudAsrPayloadAdapter {
  const _OpenRouterCloudAsrPayloadAdapter();

  @override
  bool supports({required CloudLlmConfig config, required String baseUrl}) =>
      baseUrl.contains('openrouter.ai') || config.id == 'openrouter';

  @override
  Future<void> writeRequest({
    required HttpClientRequest request,
    required String model,
    required List<int> fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    final format = mimeType == 'audio/mpeg' ? 'mp3' : 'wav';
    final payload = jsonEncode({
      'model': model,
      'input_audio': {'data': base64Encode(fileBytes), 'format': format},
    });
    request.add(utf8.encode(payload));
  }
}

class _MultipartCloudAsrPayloadAdapter extends _CloudAsrPayloadAdapter {
  const _MultipartCloudAsrPayloadAdapter();

  @override
  bool supports({required CloudLlmConfig config, required String baseUrl}) =>
      true;

  @override
  Future<void> writeRequest({
    required HttpClientRequest request,
    required String model,
    required List<int> fileBytes,
    required String fileName,
    required String mimeType,
  }) async {
    final boundary = '----yoloit-${DateTime.now().microsecondsSinceEpoch}';
    request.headers.set(
      HttpHeaders.contentTypeHeader,
      'multipart/form-data; boundary=$boundary',
    );

    void writeString(String value) => request.add(utf8.encode(value));

    writeString('--$boundary\r\n');
    writeString('Content-Disposition: form-data; name="model"\r\n\r\n');
    writeString('$model\r\n');

    writeString('--$boundary\r\n');
    writeString(
      'Content-Disposition: form-data; name="file"; filename="$fileName"\r\n',
    );
    writeString('Content-Type: $mimeType\r\n\r\n');
    request.add(fileBytes);
    writeString('\r\n');

    writeString('--$boundary--\r\n');
  }
}
