import 'dart:html' as html;

/// Opens [url] in a new browser tab.
Future<void> openUrl(String url) async {
  html.window.open(url, '_blank');
}
