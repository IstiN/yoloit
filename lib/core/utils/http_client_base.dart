import 'dart:async';

/// Cross-platform HTTP client surface used by YoLoIT.
///
/// VM and web implementations live in separate files and are swapped via
/// conditional export in `http_client.dart`.
abstract class YoloitHttpClient {
  /// Performs an HTTP GET and returns the decoded JSON body.
  ///
  /// Returns `null` on any network or parse error.
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
