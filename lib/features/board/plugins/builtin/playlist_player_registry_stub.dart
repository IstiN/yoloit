/// No-op registry for web where native media playback is unavailable.
class PlaylistPlayerRegistry {
  PlaylistPlayerRegistry._();
  static final PlaylistPlayerRegistry instance = PlaylistPlayerRegistry._();

  void release(String panelId) {}
  void notifyOpened(String panelId, String path) {}
  Future<void> applyPlaybackCommand(
    String panelId,
    Map<String, dynamic> mergedState,
  ) async {}
}
