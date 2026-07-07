import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yoloit/core/utils/http_client_base.dart';

/// Web implementation of [YoloitHttpClient] using `package:http`.
///
/// `package:http` uses `dart:html`/`fetch` under the hood on the web, so it
/// respects browser CORS policies. The response body is exposed as a stream of
/// UTF-8 byte chunks to keep the VM and web APIs identical.
class YoloitHttpClientImpl extends YoloitHttpClient
    with YoloitHttpClientGetJsonMixin {
  YoloitHttpClientImpl() : _client = http.Client();

  final http.Client _client;

  @override
  Future<String?> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final response = await _client
          .get(Uri.parse(url), headers: headers)
          .timeout(timeout);
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (e) {
      assert(() {
        debugPrint('[YoloitHttpClient] GET $url failed: $e');
        return true;
      }());
      return null;
    }
  }

  @override
  Future<Stream<List<int>>> postJsonStream(
    String url, {
    required Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await _client
        .send(
          http.Request('POST', Uri.parse(url))
            ..headers.addAll({
              'Content-Type': 'application/json; charset=utf-8',
              ...?headers,
            })
            ..body = jsonEncode(body),
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.stream.bytesToString();
      throw StateError('HTTP ${response.statusCode}: $errorBody');
    }

    return response.stream;
  }

  @override
  void close() => _client.close();
}
