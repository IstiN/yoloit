import 'package:yoloit/features/board/chat/chat_provider.dart';
import 'package:yoloit/features/board/chat/yoloit_cli_tools.dart';

void main() async {
  final executor = YoloitCliToolExecutor(execute: false);
  final result = await executor.invoke(
    'yoloit_note_append',
    <String, Object?>{'text': 'hello'},
    runtimeContext: const ChatRuntimeContext(
      boardId: 'board-1',
      panelId: 'panel-1',
    ),
  );
  print(result);
}
