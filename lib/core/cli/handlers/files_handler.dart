import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Files panels (`board.files`).
class FilesCliHandler extends PanelCliHandler {
  const FilesCliHandler();

  @override
  String get typeId => 'board.files';

  @override
  List<String> get supportedActions => ['get', 'open'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'selectedPath': panel.state['selectedPath'] ?? ''};
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
        final path = args['path'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path"');
        }
        return CliActionResult(
          message: 'Opening $path',
          stateUpdate: {'selectedPath': path},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}

/// CLI handler for File Preview panels (`board.file.preview`).
class FilePreviewCliHandler extends PanelCliHandler {
  const FilePreviewCliHandler();

  @override
  String get typeId => 'board.file.preview';

  @override
  List<String> get supportedActions => ['get', 'open'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'filePath': panel.state['filePath'] ?? ''};
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
        final path = args['path'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path"');
        }
        return CliActionResult(
          message: 'Previewing $path',
          stateUpdate: {'filePath': path},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
