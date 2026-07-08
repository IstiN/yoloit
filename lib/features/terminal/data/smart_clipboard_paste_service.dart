import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/core/cli/cli_text_argument_resolver.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';

/// Returns either inline text (for short, safe clipboard content) or an
/// absolute temp-file path containing clipboard data (for images / long text).
class SmartClipboardPasteService {
  SmartClipboardPasteService._();

  static final instance = SmartClipboardPasteService._();

  Future<String?> readInlineTextOrSavedFilePath({bool allowInlineText = false}) async {
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

    return resolveText(text, allowInlineText: allowInlineText);
  }

  /// Decides whether [text] should be pasted inline or saved to a temp file.
  /// Exposed for unit testing; callers should use [readInlineTextOrSavedFilePath].
  Future<String?> resolveText(String text, {bool allowInlineText = false}) async {
    text = ClipboardFileService.instance.normalizeText(text);

    if (text.isEmpty) return null;

    if (CliTextArgumentResolver.looksLikeTerminalOrLogDump(text)) {
      const maxChars = 1500;
      if (allowInlineText && text.length <= maxChars) return text;
      // Long terminal/log dumps are saved to a temp file so the full content is
      // preserved and can be referenced by path instead of being truncated.
      return ClipboardFileService.instance.saveTextToFile(text);
    }

    // If the clipboard contains a single existing file path, return it as-is
    // instead of wrapping it in a .txt file.
    final filePath = await ClipboardFileService.instance.tryResolveTextAsFilePath(text);
    if (filePath != null) return filePath;

    // For short, single-line, control-character-free text, paste it inline
    // when the caller opts in (e.g. chat input fields). Otherwise fall back to
    // a temp-file reference to keep terminals safe from escape sequences and
    // to give models a uniform file-based attachment.
    if (allowInlineText && ClipboardFileService.instance.isSafeInlineText(text)) {
      return text;
    }

    return ClipboardFileService.instance.saveTextToFile(text);
  }
}
