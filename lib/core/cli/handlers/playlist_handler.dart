import 'package:yoloit/core/cli/panel_cli_handler.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// CLI handler for Playlist panels (`board.playlist`).
class PlaylistCliHandler extends PanelCliHandler {
  const PlaylistCliHandler();

  @override
  String get typeId => 'board.playlist';

  @override
  List<String> get supportedActions => [
    'list',
    'add',
    'remove',
    'play',
    'pause',
    'stop',
    'next',
    'prev',
  ];

  /// Returns the `tracks` list from panel state (key used by the widget).
  List<dynamic> _tracks(BoardPanelInstance panel) =>
      panel.state['tracks'] as List<dynamic>? ?? <dynamic>[];

  @override
  Map<String, dynamic> getContent(BoardPanelInstance panel) {
    final tracks = _tracks(panel);
    final currentIndex = panel.state['currentIndex'] as int? ?? -1;
    return {
      'tracks':
          tracks
              .asMap()
              .entries
              .map(
                (e) => {
                  'index': e.key,
                  'title': (e.value as Map?)?['title'] ?? e.value,
                  'path': (e.value as Map?)?['path'] ?? '',
                  'current': e.key == currentIndex,
                },
              )
              .toList(),
      'currentIndex': currentIndex,
      'playing': panel.state['playing'] ?? false,
      'count': tracks.length,
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
          return const CliActionResult(
            ok: false,
            message: 'Missing "path" or "url"',
          );
        }
        final tracks = List<dynamic>.from(_tracks(panel));
        tracks.add({
          'path': path,
          'title': args['title'] ?? path.split('/').last,
        });
        return CliActionResult(
          message:
              'Added "${args['title'] ?? path.split('/').last}" to playlist (${tracks.length} tracks total)',
          stateUpdate: {'tracks': tracks},
        );

      case 'remove':
        final index = args['index'] as int?;
        if (index == null) {
          return const CliActionResult(ok: false, message: 'Missing "index"');
        }
        final tracks = List<dynamic>.from(_tracks(panel));
        if (index < 0 || index >= tracks.length) {
          return CliActionResult(
            ok: false,
            message: 'Index $index out of range (0–${tracks.length - 1})',
          );
        }
        final removed = (tracks[index] as Map?)?['title'] ?? 'track $index';
        tracks.removeAt(index);
        final newIndex = (panel.state['currentIndex'] as int? ?? 0).clamp(
          0,
          tracks.isEmpty ? 0 : tracks.length - 1,
        );
        return CliActionResult(
          message: 'Removed "$removed"',
          stateUpdate: {'tracks': tracks, 'currentIndex': newIndex},
        );

      case 'play':
        final tracks = _tracks(panel);
        if (tracks.isEmpty) {
          return const CliActionResult(
            ok: false,
            message:
                'Playlist is empty. Add tracks first with the "add" action.',
          );
        }
        final index = (args['index'] as int? ??
                panel.state['currentIndex'] as int? ??
                0)
            .clamp(0, tracks.length - 1);
        final title = (tracks[index] as Map?)?['title'] ?? 'track $index';
        return CliActionResult(
          message: 'Playing "$title" (track $index)',
          stateUpdate: {'currentIndex': index, 'playing': true},
        );

      case 'pause':
        return const CliActionResult(
          message: 'Paused',
          stateUpdate: {'playing': false},
        );

      case 'stop':
        return const CliActionResult(
          message: 'Stopped',
          stateUpdate: {'playing': false, 'currentIndex': 0},
        );

      case 'next':
        final tracks = _tracks(panel);
        if (tracks.isEmpty) {
          return const CliActionResult(ok: false, message: 'Playlist is empty');
        }
        final current = panel.state['currentIndex'] as int? ?? 0;
        final next = (current + 1) % tracks.length;
        final title = (tracks[next] as Map?)?['title'] ?? 'track $next';
        return CliActionResult(
          message: 'Next: "$title" (track $next)',
          stateUpdate: {'currentIndex': next, 'playing': true},
        );

      case 'prev':
        final tracks = _tracks(panel);
        if (tracks.isEmpty) {
          return const CliActionResult(ok: false, message: 'Playlist is empty');
        }
        final current = panel.state['currentIndex'] as int? ?? 0;
        final prev = current > 0 ? current - 1 : tracks.length - 1;
        final title = (tracks[prev] as Map?)?['title'] ?? 'track $prev';
        return CliActionResult(
          message: 'Previous: "$title" (track $prev)',
          stateUpdate: {'currentIndex': prev, 'playing': true},
        );

      default:
        return CliActionResult(ok: false, message: 'Unknown action: $action');
    }
  }

  @override
  Map<String, CliActionHelp> get actionHelp => {
    'list': const CliActionHelp(
      description: 'List playlist tracks and playback state',
    ),
    'add': const CliActionHelp(
      description: 'Add a media file or URL to the playlist',
      params: {
        'path': 'Media file path',
        'url': 'Media URL',
        'title': 'Optional title',
      },
    ),
    'remove': const CliActionHelp(
      description: 'Remove a track by zero-based index',
      params: {'index': 'Zero-based track index'},
    ),
    'play': const CliActionHelp(
      description: 'Start playback, optionally at a track index',
      params: {'index': 'Optional zero-based track index'},
    ),
    'pause': const CliActionHelp(description: 'Pause playback'),
    'stop': const CliActionHelp(
      description: 'Stop playback and reset to the first track',
    ),
    'next': const CliActionHelp(description: 'Skip to next track'),
    'prev': const CliActionHelp(description: 'Skip to previous track'),
  };
}
