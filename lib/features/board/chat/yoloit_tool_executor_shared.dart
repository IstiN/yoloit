import 'dart:convert';

import 'package:yoloit/features/board/chat/yoloit_tool_catalog.dart';

/// Resolves a YoLoIT tool [functionName] to its catalog entry.
///
/// Returns the resolved [tool] and `null` error, or `null` tool and a JSON
/// error/response string (for meta commands such as `get_tools`).
({YoloitCliTool? tool, String? response}) resolveToolCall(
  String functionName,
) {
  if (functionName == 'get_tools' || functionName == 'list_tools') {
    return (tool: null, response: YoloitCliToolCatalog.compactToolsJson());
  }
  final tool = YoloitCliToolCatalog.byFunctionName(functionName);
  if (tool == null) {
    return (
      tool: null,
      response: jsonEncode(<String, Object?>{
          'ok': false,
          'error': 'Unknown YoLoIT tool: $functionName',
        },
      ),
    );
  }
  return (tool: tool, response: null);
}
