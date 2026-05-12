import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for File Tree panels (`board.filetree`).
class FileTreeCliHandler extends PanelCliHandler {
  const FileTreeCliHandler();

  @override
  String get typeId => 'board.filetree';

  @override
  List<String> get supportedActions => [
    'list',
    'open',
    'expand',
    'collapse',
    'set-root',
    'refresh',
  ];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'rootPath': panel.state['rootPath'] ?? '',
      'expandedDirs': panel.state['expandedDirs'] ?? <String>[],
      'selectedFile': panel.state['selectedFile'] ?? '',
    };
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'list':
        return CliActionResult(data: getContent(panel));

      case 'open':
        final path = args['path'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path"');
        }
        return CliActionResult(
          message: 'Selected $path',
          stateUpdate: {'selectedFile': path},
        );

      case 'expand':
        final dir = args['dir'] as String?;
        if (dir == null) {
          return const CliActionResult(ok: false, message: 'Missing "dir"');
        }
        final expanded = List<String>.from(
          panel.state['expandedDirs'] as List? ?? <String>[],
        );
        if (!expanded.contains(dir)) expanded.add(dir);
        return CliActionResult(
          message: 'Expanded $dir',
          stateUpdate: {'expandedDirs': expanded},
        );

      case 'collapse':
        final dir = args['dir'] as String?;
        if (dir == null) {
          return const CliActionResult(ok: false, message: 'Missing "dir"');
        }
        final expanded = List<String>.from(
          panel.state['expandedDirs'] as List? ?? <String>[],
        )..remove(dir);
        return CliActionResult(
          message: 'Collapsed $dir',
          stateUpdate: {'expandedDirs': expanded},
        );

      case 'set-root':
        final path = args['path'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path"');
        }
        return CliActionResult(
          message: 'Root set to $path',
          stateUpdate: {
            'rootPath': path,
            'expandedDirs': <String>[],
            'selectedFile': '',
          },
        );

      case 'refresh':
        return CliActionResult(
          message: 'Refreshed',
          stateUpdate: {'_refreshAt': DateTime.now().toIso8601String()},
        );

      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
