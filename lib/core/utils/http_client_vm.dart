import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:yoloit/core/utils/http_client_base.dart';

/// VM implementation of [YoloitHttpClient] using `dart:io` [HttpClient].
class YoloitHttpClientImpl extends YoloitHttpClient
    with YoloitHttpClientGetJsonMixin {
  YoloitHttpClientImpl() : _client = HttpClient();

  final HttpClient _client;

  @override
  Future<String?> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    try {
      final request = await _client.getUrl(Uri.parse(url)).timeout(timeout);
      headers?.forEach(request.headers.set);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) return null;
      return await response.transform(utf8.decoder).join().timeout(timeout);
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
    final request = await _client.postUrl(Uri.parse(url)).timeout(timeout);
    request.headers.set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');
    headers?.forEach(request.headers.set);
    request.add(utf8.encode(jsonEncode(body)));
    final response = await request.close().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await response.transform(utf8.decoder).join();
      throw StateError('HTTP ${response.statusCode}: $errorBody');
    }
    return response;
  }

  @override
  void close() => _client.close(force: true);
}
