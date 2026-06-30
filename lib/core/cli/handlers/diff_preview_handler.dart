import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Diff Preview panels (`board.diff.preview`).
class DiffPreviewCliHandler extends PanelCliHandler {
  const DiffPreviewCliHandler();

  @override
  String get typeId => 'board.diff.preview';

  @override
  List<String> get supportedActions => ['get', 'open', 'set-root'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'filePath': panel.state['filePath'] ?? '',
      'rootPath': panel.state['rootPath'] ?? '',
      'title': panel.state['title'] ?? '',
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
      case 'open':
        final path = args['path'] ?? args['filePath'];
        if (path == null || path.toString().trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "path" field',
          );
        }
        final update = <String, dynamic>{'filePath': path.toString()};
        final title = args['title'];
        if (title != null) {
          update['title'] = title.toString();
        }
        return CliActionResult(
          message: 'Diff preview opened for ${path.toString()}',
          stateUpdate: update,
        );
      case 'set-root':
        final root = args['rootPath'] ?? args['path'];
        if (root == null || root.toString().trim().isEmpty) {
          return const CliActionResult(
            ok: false,
            message: 'Missing "rootPath" field',
          );
        }
        return CliActionResult(
          message: 'Diff root set to ${root.toString()}',
          stateUpdate: {'rootPath': root.toString()},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read diff preview panel state'),
    'open': const CliActionHelp(
      description: 'Open a file in the diff preview panel',
      params: {
        'path': 'Absolute file path (required)',
        'title': 'Optional panel title override',
      },
    ),
    'set-root': const CliActionHelp(
      description: 'Set repository root for diff context',
      params: {'rootPath': 'Absolute repository root path (required)'},
    ),
  };
}
