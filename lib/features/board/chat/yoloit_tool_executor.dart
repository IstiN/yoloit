import 'package:yoloit/features/board/chat/yoloit_tool_executor_base.dart';
import 'package:yoloit/features/board/chat/yoloit_tool_executor_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';

export 'package:yoloit/features/board/chat/yoloit_tool_executor_base.dart';
export 'package:yoloit/features/board/chat/yoloit_tool_executor_vm.dart'
    if (dart.library.html) 'package:yoloit/features/board/chat/yoloit_tool_executor_web.dart';

YoloitToolExecutor createYoloitToolExecutor() =>
    createPlatformToolExecutor();
