import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

import 'package:yoloit/core/cli/panel_getopen_cli_handler.dart';

/// CLI handler for File Tree panels (`board.filetree`).
class FileTreeCliHandler extends PanelCliHandler with PanelGetOpenCliHandler {
  const FileTreeCliHandler();

  @override
  String get typeId => 'board.filetree';

  @override
  String get openPathKey => 'selectedFile';

  @override
  String get openMessage => 'Selected';

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

  (String, List<String>)? _dirExpansion(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final dir = args['dir'] as String?;
    if (dir == null) return null;
    final expanded = List<String>.from(
      panel.state['expandedDirs'] as List? ?? <String>[],
    );
    return (dir, expanded);
  }

  @override
  Future<CliActionResult> handleAction(
    String action,
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) async {
    switch (action) {
      case 'expand':
        final parsed = _dirExpansion(args, panel);
        if (parsed == null) {
          return const CliActionResult(ok: false, message: 'Missing "dir"');
        }
        final (dir, expanded) = parsed;
        if (!expanded.contains(dir)) expanded.add(dir);
        return CliActionResult(
          message: 'Expanded $dir',
          stateUpdate: {'expandedDirs': expanded},
        );

      case 'collapse':
        final parsed = _dirExpansion(args, panel);
        if (parsed == null) {
          return const CliActionResult(ok: false, message: 'Missing "dir"');
        }
        final (dir, expanded) = parsed;
        expanded.remove(dir);
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
        return super.handleAction(action, args, panel);
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'list': const CliActionHelp(description: 'Read file tree panel state'),
    'open': const CliActionHelp(
      description: 'Select a file path in the tree',
      params: {'path': 'Absolute file path'},
    ),
    'expand': const CliActionHelp(
      description: 'Expand a directory in the tree',
      params: {'dir': 'Absolute directory path'},
    ),
    'collapse': const CliActionHelp(
      description: 'Collapse a directory in the tree',
      params: {'dir': 'Absolute directory path'},
    ),
    'set-root': const CliActionHelp(
      description: 'Set the root directory shown by the tree',
      params: {'path': 'Absolute root directory path'},
    ),
    'refresh': const CliActionHelp(description: 'Refresh file tree contents'),
  };
}
