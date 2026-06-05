import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Mixin for panel CLI handlers that only need standard `get` and `open`
/// actions.
///
/// [openPathKey] is the state key written when `open` is called.
/// [openMessage] is the human-readable result message.
mixin PanelGetOpenCliHandler on PanelCliHandler {
  String get openPathKey;
  String get openMessage;

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'get':
        return CliActionResult(data: getContent(panel));
      case 'open':
        final path = args['path'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path"');
        }
        return CliActionResult(
          message: '$openMessage $path',
          stateUpdate: buildOpenStateUpdate(path),
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  Map<String, dynamic> buildOpenStateUpdate(String path) {
    return {openPathKey: path};
  }
}
