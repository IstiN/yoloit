import 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper_web.dart';

export 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/helpers/chat_file_opener_helper_web.dart';

typedef CreatePreviewPanel = Future<String?> Function(
  String typeId,
  Map<String, dynamic> state,
  String title,
);

Future<void> openChatFile(
  String path, {
  CreatePreviewPanel? createPreviewPanel,
}) => ChatFileOpener.open(path, createPreviewPanel: createPreviewPanel);
