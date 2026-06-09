import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';

/// Returns either inline text (for short text clipboard content) or an absolute
/// temp-file path containing clipboard data (for images / long text).
class SmartClipboardPasteService {
  SmartClipboardPasteService._();

  static final instance = SmartClipboardPasteService._();

  Future<String?> readInlineTextOrSavedFilePath({
    int inlineWordLimit = 1000,
  }) async {
    String? text;

    // Try super_clipboard first.
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();

        // Images always become temp files so terminals/chats can reference them.
        if (reader.canProvide(Formats.png) ||
            reader.canProvide(Formats.jpeg)) {
          return ClipboardFileService.instance.saveClipboardToFile();
        }

        if (reader.canProvide(Formats.plainText)) {
          text = await reader.readValue(Formats.plainText);
        }
      }
    } catch (_) {
      // ignore super_clipboard failures
    }

    // Fallback to Flutter's standard clipboard API.
    if (text == null || text.isEmpty) {
      try {
        final data = await Clipboard.getData('text/plain');
        text = data?.text;
      } catch (_) {
        // ignore fallback failures
      }
    }

    if (text == null || text.isEmpty) return null;

    final wordCount = text.trim().split(RegExp(r'\s+')).length;
    if (wordCount <= inlineWordLimit) {
      return text;
    }
    return ClipboardFileService.instance.saveClipboardToFile();
  }
}
