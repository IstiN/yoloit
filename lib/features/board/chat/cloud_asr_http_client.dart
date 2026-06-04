import 'dart:convert';
import 'dart:io';

/// Builds the JSON payload for an LLM chat-completion request that
/// includes base64-encoded audio and a transcription prompt.
String buildChatAudioPayload({
  required String model,
  required List<int> audioBytes,
  required String format,
}) {
  return jsonEncode({
    'model': model,
    'messages': [
      {
        'role': 'user',
        'content': [
          {
            'type': 'input_audio',
            'input_audio': {
              'data': base64Encode(audioBytes),
              'format': format,
            },
          },
          {
            'type': 'text',
            'text':
                'Transcribe this audio exactly as spoken. '
                'Output only the transcription text, nothing else.',
          },
        ],
      },
    ],
  });
}

/// POSTs [payload] to the chat-completions endpoint at [baseUrl] and
/// extracts the assistant's text content from the response.
///
/// Throws [StateError] on non-2xx status codes or unexpected response
/// structure.
Future<String> postChatCompletion({
  required String baseUrl,
  required String apiKey,
  required Map<String, String> extraHeaders,
  required String payload,
}) async {
  final normalizedBase = baseUrl.replaceFirst(RegExp(r'/+$'), '');
  final uri = Uri.parse('$normalizedBase/chat/completions');
  final client = HttpClient();
  try {
    final request = await client.postUrl(uri);
    request.headers.set(
      HttpHeaders.authorizationHeader,
      'Bearer $apiKey',
    );
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
    for (final entry in extraHeaders.entries) {
      request.headers.set(entry.key, entry.value);
    }
    request.add(utf8.encode(payload));
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError(
        'Cloud ASR (LLM) failed (${response.statusCode}): '
        '${body.length > 600 ? '${body.substring(0, 600)}…' : body}',
      );
    }
    final decoded = jsonDecode(body);
    if (decoded is Map) {
      final choices = decoded['choices'];
      if (choices is List && choices.isNotEmpty) {
        final content = choices.first['message']?['content'];
        if (content is String) return content.trim();
      }
    }
    throw StateError('Cloud ASR (LLM) returned unexpected response: $body');
  } finally {
    client.close(force: true);
  }
}
