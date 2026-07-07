import 'package:yoloit/features/board/chat/helpers/chat_mic_helper_base.dart';
import 'package:yoloit/features/board/chat/helpers/chat_mic_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_mic_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_mic_helper_base.dart';
export 'package:yoloit/features/board/chat/helpers/chat_mic_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_mic_helper_web.dart';

ChatMicHandler createChatMicHandler() => ChatMicHandlerImpl();
