import 'dart:convert';

import 'package:shelf/shelf.dart' as shelf;
import 'package:yoloit/core/remote/server_process_utils.dart';

/// Minimal host exposing the [ServerProcessMixin] state maps for tests.
class ProcessHost with ServerProcessMixin {}

/// Builds a JSON [shelf.Request] the way the remote servers receive it.
shelf.Request shelfRequest(
  String method,
  String url, {
  Object? body,
  Map<String, String>? headers,
}) {
  return shelf.Request(
    method,
    Uri.parse(url),
    headers: headers ?? const <String, String>{},
    body: body == null ? null : jsonEncode(body),
  );
}

/// Decodes a JSON [shelf.Response] body into a map.
Future<Map<String, dynamic>> decodeShelfJson(shelf.Response response) async {
  final text = await response.readAsString();
  return Map<String, dynamic>.from(jsonDecode(text) as Map);
}
