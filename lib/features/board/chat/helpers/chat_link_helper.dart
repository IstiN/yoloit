import 'package:yoloit/features/board/chat/helpers/chat_link_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_link_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_link_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_link_helper_web.dart';

Future<void> openChatLink(String url) => ChatLinkHelper.open(url);
