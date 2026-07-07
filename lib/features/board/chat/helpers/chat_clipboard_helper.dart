import 'package:yoloit/features/board/chat/helpers/chat_clipboard_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_clipboard_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_clipboard_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_clipboard_helper_web.dart';

Future<String?> readChatClipboardInlineText() => ChatClipboardHelper.read();
