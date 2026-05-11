import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Webpage/Browser panels (`board.webpage`).
class WebpageCliHandler extends PanelCliHandler {
  const WebpageCliHandler();

  @override
  String get typeId => 'board.webpage';

  @override
  List<String> get supportedActions => ['open', 'get'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'url': panel.state['url'] ?? ''};
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'open':
        final url = args['url'] as String?;
        if (url == null || url.isEmpty) {
          return const CliActionResult(ok: false, message: 'Missing "url" field');
        }
        return CliActionResult(
          message: 'Opening $url',
          stateUpdate: {'url': url},
        );
      case 'get':
        return CliActionResult(
          data: {'url': panel.state['url'] ?? ''},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
