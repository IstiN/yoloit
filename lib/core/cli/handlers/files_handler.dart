import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/core/cli/panel_getopen_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

class FilesCliHandler extends PanelCliHandler with PanelGetOpenCliHandler {
  const FilesCliHandler();

  @override
  String get typeId => 'board.files';

  @override
  List<String> get supportedActions => ['get', 'open'];

  @override
  String get openPathKey => 'selectedPath';

  @override
  String get openMessage => 'Opening';

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {'selectedPath': panel.state['selectedPath'] ?? ''};
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'get': const CliActionHelp(description: 'Read selected folder path'),
    'open': const CliActionHelp(
      description: 'Select a folder or file path in the files panel',
      params: {'path': 'Absolute file or folder path'},
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
