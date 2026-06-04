import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Perform a simple HTTP GET and decode the response as JSON.
///
/// Returns `null` on any network or parse error.  If [client] is provided it
/// is reused but **not** closed; otherwise a temporary [HttpClient] is
/// created and closed automatically.
Future<Map<String, dynamic>?> fetchJson({
  required String url,
  required Duration timeout,
  Map<String, String>? headers,
  String userAgent = 'YoLoIT',
  HttpClient? client,
}) async {
  final ownClient = client == null;
  final c = client ?? HttpClient();
  if (ownClient) c.connectionTimeout = timeout;
  try {
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set(HttpHeaders.userAgentHeader, userAgent);
    headers?.forEach(req.headers.set);
    final resp = await req.close().timeout(timeout);
    if (resp.statusCode != 200) return null;
    final body = await resp.transform(utf8.decoder).join().timeout(timeout);
    return jsonDecode(body) as Map<String, dynamic>;
  } catch (e) {
    debugPrint('[fetchJson] $url failed: $e');
    return null;
  } finally {
    if (ownClient) c.close(force: true);
  }
}
