import 'package:flutter/services.dart';

abstract class ChatClipboardHelper {
  static Future<String?> read() async {
    try {
      final data = await Clipboard.getData('text/plain');
      return data?.text;
    } catch (_) {
      return null;
    }
  }
}
