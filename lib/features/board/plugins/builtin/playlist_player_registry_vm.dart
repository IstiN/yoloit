import 'package:media_kit/media_kit.dart';

/// Keeps [Player] instances alive across board switches so playback is
/// not interrupted when the user navigates away from the board containing
/// a playlist panel.
///
/// Players are keyed by panel ID and persist until [release] is called
/// explicitly (e.g. when the panel is deleted).
class PlaylistPlayerRegistry {
  PlaylistPlayerRegistry._();
  static final PlaylistPlayerRegistry instance = PlaylistPlayerRegistry._();

  final Map<String, Player> _players = {};
  // Track which path each player currently has open so we can resume vs. re-open.
  final Map<String, String> _openedPath = {};

  /// Returns the existing player for [panelId] or creates a new one.
  Player acquire(String panelId) {
    return _players.putIfAbsent(panelId, Player.new);
  }

  /// Releases and disposes the player for [panelId].
  /// Call this when the panel itself is deleted (not just hidden).
  void release(String panelId) {
    _openedPath.remove(panelId);
    final p = _players.remove(panelId);
    p?.dispose();
  }

  /// Whether a player exists for [panelId] and is currently playing.
  bool isPlaying(String panelId) => _players[panelId]?.state.playing ?? false;

  /// Notify the registry that [panelId] has opened [path].
  /// Called from the playlist widget so the registry can skip re-opening the same file.
  void notifyOpened(String panelId, String path) {
    _openedPath[panelId] = path;
  }

  /// Directly trigger playback for the given panel state.
  ///
  /// Called from the CLI server so that play/pause/next/prev work even when
  /// the playlist widget is not mounted (e.g. user is on a different board).
  Future<void> applyPlaybackCommand(
    String panelId,
    Map<String, dynamic> mergedState,
  ) async {
    final tracks = mergedState['tracks'] as List<dynamic>? ?? [];
    final idx = (mergedState['currentIndex'] as int? ?? 0)
        .clamp(0, tracks.isEmpty ? 0 : tracks.length - 1);
    final playing = mergedState['playing'] as bool? ?? false;

    if (tracks.isEmpty) return;

    final player = acquire(panelId);

    if (playing) {
      final path = (tracks[idx] as Map?)?['path'] as String? ?? '';
      if (path.isEmpty) return;
      final alreadyOpen = _openedPath[panelId] == path;
      if (alreadyOpen && !player.state.playing) {
        // Same track, just paused — resume instead of restarting.
        await player.play();
      } else if (!alreadyOpen) {
        // Different track (or first play) — open and play.
        _openedPath[panelId] = path;
        await player.open(Media(path), play: true);
      }
      // else: already playing this track, nothing to do
    } else {
      if (player.state.playing) {
        await player.pause();
      }
    }
  }
}
