import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';

abstract class ChatClipboardHelper {
  static Future<String?> read() async {
    try {
      return await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
    } catch (_) {
      return null;
    }
  }
}
