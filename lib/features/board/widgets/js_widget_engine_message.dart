import 'dart:convert';

/// Wire format used by the web JS widget engine.
///
/// Messages are JSON strings prefixed with `__yoloit__` so that the host and
/// the iframe can safely ignore unrelated postMessage traffic.
class JsWidgetMessage {
  JsWidgetMessage({required this.channel, required this.payload});

  final String channel;
  final dynamic payload;

  static const _prefix = '__yoloit__';

  /// Decodes a raw incoming string. Returns null when the string is not a
  /// yoloit message.
  static JsWidgetMessage? tryParse(String raw) {
    if (!raw.startsWith(_prefix)) return null;
    final json = raw.substring(_prefix.length);
    final decoded = jsonDecode(json) as Map<String, dynamic>?;
    if (decoded == null) return null;
    return JsWidgetMessage(
      channel: decoded['channel'] as String? ?? '',
      payload: decoded['payload'],
    );
  }

  /// Encodes a message for sending to the iframe or to Dart.
  static String encode({required String channel, required dynamic payload}) {
    return '$_prefix${jsonEncode({'channel': channel, 'payload': payload})}';
  }

  /// Encodes a generic call/event message using a JS channel name.
  static String encodeJsCall(String channel, dynamic payload) =>
      encode(channel: channel, payload: payload);
}
