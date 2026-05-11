import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Playlist panels (`board.playlist`).
class PlaylistCliHandler extends PanelCliHandler {
  const PlaylistCliHandler();

  @override
  String get typeId => 'board.playlist';

  @override
  List<String> get supportedActions => ['list', 'add', 'remove', 'play', 'pause', 'stop', 'next', 'prev'];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    return {
      'playlist': panel.state['playlist'] as List<dynamic>? ?? <dynamic>[],
      'currentIndex': panel.state['currentIndex'] ?? -1,
      'playing': panel.state['playing'] ?? false,
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
      case 'add':
        final path = args['path'] as String? ?? args['url'] as String?;
        if (path == null) {
          return const CliActionResult(ok: false, message: 'Missing "path" or "url"');
        }
        final playlist = List<dynamic>.from(
          (panel.state['playlist'] as List<dynamic>?) ?? <dynamic>[],
        );
        playlist.add({'path': path, 'title': args['title'] ?? path.split('/').last});
        return CliActionResult(
          message: 'Added to playlist',
          stateUpdate: {'playlist': playlist},
        );
      case 'remove':
        final index = args['index'] as int?;
        if (index == null) {
          return const CliActionResult(ok: false, message: 'Missing "index"');
        }
        final playlist = List<dynamic>.from(
          (panel.state['playlist'] as List<dynamic>?) ?? <dynamic>[],
        );
        if (index < 0 || index >= playlist.length) {
          return const CliActionResult(ok: false, message: 'Index out of range');
        }
        playlist.removeAt(index);
        return CliActionResult(
          message: 'Removed from playlist',
          stateUpdate: {'playlist': playlist},
        );
      case 'play':
        final index = args['index'] as int? ?? panel.state['currentIndex'] ?? 0;
        return CliActionResult(
          message: 'Playing track $index',
          stateUpdate: {'currentIndex': index, 'playing': true},
        );
      case 'pause':
        return CliActionResult(
          message: 'Paused',
          stateUpdate: {'playing': false},
        );
      case 'stop':
        return CliActionResult(
          message: 'Stopped',
          stateUpdate: {'playing': false, 'currentIndex': -1},
        );
      case 'next':
        final playlist = panel.state['playlist'] as List<dynamic>? ?? [];
        final current = panel.state['currentIndex'] as int? ?? 0;
        final next = (current + 1) % playlist.length;
        return CliActionResult(
          message: 'Next track: $next',
          stateUpdate: {'currentIndex': next, 'playing': true},
        );
      case 'prev':
        final playlist = panel.state['playlist'] as List<dynamic>? ?? [];
        final current = panel.state['currentIndex'] as int? ?? 0;
        final prev = current > 0 ? current - 1 : playlist.length - 1;
        return CliActionResult(
          message: 'Previous track: $prev',
          stateUpdate: {'currentIndex': prev, 'playing': true},
        );
      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }
}
