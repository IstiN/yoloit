import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Cross-platform HTTP client surface used by YoLoIT.
///
/// VM and web implementations live in separate files and are swapped via
/// conditional export in `http_client.dart`.
abstract class YoloitHttpClient {
  /// Performs an HTTP GET and returns the response body as a UTF-8 string.
  ///
  /// Returns `null` on any network or non-2xx error.
  Future<String?> getString(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  });

  /// Performs an HTTP GET and returns the decoded JSON body.
  ///
  /// Returns `null` on any network, non-2xx, or parse error.
  Future<Map<String, dynamic>?> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  });

  /// Performs an HTTP POST with a JSON body and returns a byte stream of the
  /// response body.
  ///
  /// The caller is responsible for decoding SSE chunks. Throws on network
  /// errors or non-2xx status codes.
  Future<Stream<List<int>>> postJsonStream(
    String url, {
    required Object? body,
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 30),
  });

  void close();
}

/// Shared [getJson] implementation in terms of [getString].
///
/// VM and web implementations use this mixin so the JSON decoding / error
/// handling code is not duplicated between platforms.
mixin YoloitHttpClientGetJsonMixin on YoloitHttpClient {
  @override
  Future<Map<String, dynamic>?> getJson(
    String url, {
    Map<String, String>? headers,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final body = await getString(url, headers: headers, timeout: timeout);
    if (body == null) return null;
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (e) {
      assert(() {
        debugPrint('[YoloitHttpClient] JSON decode $url failed: $e');
        return true;
      }());
      return null;
    }
  }
}
