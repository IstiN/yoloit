import 'dart:html' as html;

abstract class ChatLinkHelper {
  static Future<void> open(String url) async {
    html.window.open(url, '_blank');
  }
}
