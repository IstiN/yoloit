import 'package:flutter/services.dart';

/// Abstraction over the system clipboard so tests can inject a fake.
abstract class ClipboardInterface {
  /// Copies [text] to the clipboard.
  Future<void> setText(String text);

  /// Reads plain text from the clipboard.
  Future<String?> getText();
}

/// Default implementation that delegates to Flutter's [Clipboard].
class SystemClipboard implements ClipboardInterface {
  const SystemClipboard();

  @override
  Future<void> setText(String text) => Clipboard.setData(ClipboardData(text: text));

  @override
  Future<String?> getText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    return data?.text;
  }
}

/// Copies [text] to the system clipboard.
Future<void> copyToClipboard(String text) => const SystemClipboard().setText(text);

/// Reads plain text from the system clipboard, returning `null` if unavailable.
Future<String?> readClipboard() => const SystemClipboard().getText();
