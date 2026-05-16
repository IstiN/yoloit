import 'package:flutter/services.dart';

const yoloChatSystemPromptAsset = 'assets/prompts/yolo_chat_system_prompt.md';

const _fallbackYoloChatSystemPrompt = '''
You are YoLo Assistant, the YoLoIT chat UI assistant.

Use available YoLoIT function tools for board/UI actions instead of only explaining. Previous chat messages and previous tool calls are part of conversation state. For destructive actions ask for confirmation first. Keep final answers concise.
''';

Future<String> loadYoloChatSystemPrompt() async {
  try {
    return (await rootBundle.loadString(yoloChatSystemPromptAsset)).trim();
  } catch (_) {
    return _fallbackYoloChatSystemPrompt.trim();
  }
}
