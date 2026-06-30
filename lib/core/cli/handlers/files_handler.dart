import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/cli/panel_getopen_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class FilesCliHandler extends PanelCliHandler with PanelGetOpenCliHandler {
  const FilesCliHandler();

  @override
  String get typeId => 'board.files';

  @override
  List<String> get supportedActions => ['get', 'open', 'list', 'add', 'remove'];

  @override
  String get openPathKey => 'selectedPath';

  @override
  String get openMessage => 'Opening';

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'files': _files(panel),
      'selectedPath': panel.state['selectedPath'] ?? '',
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
        return CliActionResult(
          data: {
            'files': _files(panel),
            'count': _files(panel).length,
          },
        );
      case 'add':
        return _handleAdd(args, panel);
      case 'remove':
        return _handleRemove(args, panel);
      default:
        return super.handleAction(action, args, panel);
    }
  }

  CliActionResult _handleAdd(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final path = args['path'] as String? ?? args['filePath'] as String?;
    if (path == null || path.trim().isEmpty) {
      return const CliActionResult(ok: false, message: 'Missing "path" field');
    }
    final normalizedPath = path.trim();
    final files = _files(panel);
    if (files.any((file) => file['path'] == normalizedPath)) {
      return CliActionResult(
        ok: false,
        message: 'File already listed: $normalizedPath',
      );
    }
    final name = args['name'] as String? ?? _basename(normalizedPath);
    final entry = {
      'id': '${DateTime.now().millisecondsSinceEpoch}$name',
      'path': normalizedPath,
      'name': name,
      'addedAt': DateTime.now().toIso8601String(),
    };
    return CliActionResult(
      message: 'Added $name',
      stateUpdate: {'files': [...files, entry]},
      data: entry,
    );
  }

  CliActionResult _handleRemove(
    Map<String, dynamic> args,
    BoardPanelInstance panel,
  ) {
    final files = _files(panel);
    final id = args['id'] as String?;
    final path = args['path'] as String? ?? args['filePath'] as String?;
    if (id != null && id.isNotEmpty) {
      final filtered = files.where((file) => file['id'] != id).toList();
      if (filtered.length == files.length) {
        return CliActionResult(ok: false, message: 'File id not found: $id');
      }
      return CliActionResult(
        message: 'Removed file $id',
        stateUpdate: {'files': filtered},
      );
    }
    if (path != null && path.trim().isNotEmpty) {
      final normalized = path.trim();
      final filtered =
          files.where((file) => file['path'] != normalized).toList();
      if (filtered.length == files.length) {
        return CliActionResult(
          ok: false,
          message: 'File path not found: $normalized',
        );
      }
      return CliActionResult(
        message: 'Removed $normalized',
        stateUpdate: {'files': filtered},
      );
    }
    return const CliActionResult(
      ok: false,
      message: 'Missing "id" or "path" field',
    );
  }

  List<Map<String, dynamic>> _files(BoardPanelInstance panel) {
    return (panel.state['files'] as List?)
            ?.whereType<Map<dynamic, dynamic>>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList() ??
        [];
  }

  String _basename(String path) {
    final parts = path.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(
      description: 'Read files panel state (files list and selected path)',
    ),
    'list': const CliActionHelp(description: 'List files attached to the panel'),
    'open': const CliActionHelp(
      description: 'Select a folder or file path in the files panel',
      params: {'path': 'Absolute file or folder path'},
    ),
    'add': const CliActionHelp(
      description: 'Attach a file path to the files panel',
      params: {
        'path': 'Absolute file path (required)',
        'name': 'Optional display name',
      },
    ),
    'remove': const CliActionHelp(
      description: 'Remove a file from the files panel',
      params: {
        'id': 'File entry id',
        'path': 'Absolute file path (alternative to id)',
      },
    ),
  };
}

class FilePreviewCliHandler extends PanelCliHandler with PanelGetOpenCliHandler {
  const FilePreviewCliHandler();

  @override
  String get typeId => 'board.file.preview';

  @override
  List<String> get supportedActions => ['get', 'open'];

  @override
  String get openPathKey => 'path';

  @override
  String get openMessage => 'Previewing';

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final path = panel.state['path'] ?? panel.state['filePath'] ?? '';
    return {'path': path, 'filePath': path};
  }

  @override
  Map<String, dynamic> buildOpenStateUpdate(String path) {
    return {'path': path, 'filePath': path};
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read current preview file path'),
    'open': const CliActionHelp(
      description: 'Open a file in the file preview panel',
      params: {
        'path':
            'Absolute file path; supports images, text, markdown, media, and PDF',
      },
    ),
  };
}