import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Code Snippet panels (`board.code.snippet`).
class CodeSnippetCliHandler extends PanelCliHandler {
  const CodeSnippetCliHandler();

  @override
  String get typeId => 'board.code.snippet';

  @override
  List<String> get supportedActions => ['get', 'set'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'language': panel.state['language'] ?? 'plaintext',
      'code': panel.state['code'] ?? '',
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'set':
        final code = args['code'] as String?;
        if (code == null) {
          return const CliActionResult(ok: false, message: 'Missing "code" field');
        }
        final lang = args['language'] as String?;
        return CliActionResult(
          message: 'Code updated',
          stateUpdate: {
            'code': code,
            if (lang != null) 'language': lang,
          },
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
