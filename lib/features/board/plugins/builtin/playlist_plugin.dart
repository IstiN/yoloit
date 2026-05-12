import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yoloit/core/theme/app_color_scheme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';

// ─── Player registry ──────────────────────────────────────────────────────────

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

  /// Returns the existing player for [panelId] or creates a new one.
  Player acquire(String panelId) {
    return _players.putIfAbsent(panelId, Player.new);
  }

  /// Releases and disposes the player for [panelId].
  /// Call this when the panel itself is deleted (not just hidden).
  void release(String panelId) {
    final p = _players.remove(panelId);
    p?.dispose();
  }

  /// Whether a player exists for [panelId] and is currently playing.
  bool isPlaying(String panelId) => _players[panelId]?.state.playing ?? false;
}


/// Board panel plugin: media playlist player (audio + video).
///
/// Panel state JSON schema:
/// ```json
/// {
///   "tracks": [
///     { "id": "<unique>", "path": "/abs/path/to/file", "name": "song.mp3" }
///   ],
///   "currentIndex": 0,
///   "repeat": false,
///   "shuffle": false
/// }
/// ```
/// This schema is intentionally simple so panels can be created programmatically
/// via terminal commands or a remote server by POSTing the JSON config + state.
class PlaylistPlugin extends BoardPanelPlugin {
  const PlaylistPlugin();

  static const String kTypeId = 'board.playlist';

  @override
  String get typeId => kTypeId;

  @override
  String get displayName => 'Playlist';

  @override
  IconData get icon => Icons.queue_music_rounded;

  @override
  Color get accentColor => const Color(0xFF8B5CF6);

  @override
  Size get defaultSize => const Size(380, 480);

  @override
  Map<String, dynamic> get initialState => {
    'tracks': <Map<String, dynamic>>[],
    'currentIndex': 0,
    'repeat': false,
    'shuffle': false,
  };

  @override
  Widget buildContent(
    BuildContext context,
    BoardPanelInstance panel,
    BoardPanelRenderContext renderContext,
  ) =>
      _PlaylistContent(panel: panel, renderContext: renderContext);
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

bool _isVideoExt(String ext) => const {
  'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v',
}.contains(ext.toLowerCase());

bool _isAudioExt(String ext) => const {
  'mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg',
}.contains(ext.toLowerCase());

bool _isMediaExt(String ext) => _isVideoExt(ext) || _isAudioExt(ext);

String _ext(String path) {
  final parts = path.split('.');
  return parts.length > 1 ? parts.last : '';
}

String _formatDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '$m:$s';
}

// ─── State helpers ────────────────────────────────────────────────────────────

List<Map<String, dynamic>> _parseTracks(BoardPanelInstance panel) =>
    (panel.state['tracks'] as List?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList() ??
    [];

// ─── Main content widget ──────────────────────────────────────────────────────

class _PlaylistContent extends StatefulWidget {
  const _PlaylistContent({required this.panel, required this.renderContext});

  final BoardPanelInstance panel;
  final BoardPanelRenderContext renderContext;

  @override
  State<_PlaylistContent> createState() => _PlaylistContentState();
}

class _PlaylistContentState extends State<_PlaylistContent> {
  static const Color _accent = Color(0xFF8B5CF6);

  late Player _player;
  VideoController? _videoCtrl;
  bool _videoVisible = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  final List<StreamSubscription<dynamic>> _subs = [];
  final _random = Random();

  // ── State accessors ────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get _tracks => _parseTracks(widget.panel);
  int get _currentIndex =>
      (widget.panel.state['currentIndex'] as int? ?? 0)
          .clamp(0, (_tracks.isEmpty ? 0 : _tracks.length - 1));
  bool get _repeat => widget.panel.state['repeat'] as bool? ?? false;
  bool get _shuffle => widget.panel.state['shuffle'] as bool? ?? false;

  bool _userInitiated = false; // true when index change was triggered by user

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // Use registry so the player survives board switches (widget dispose/remount).
    _player = PlaylistPlayerRegistry.instance.acquire(widget.panel.id);
    _subscribeToPlayer();
    // Only open the track if nothing is currently playing (i.e. first mount).
    if (!_player.state.playing) {
      _openCurrentTrack(autoPlay: false);
    } else {
      // Re-sync UI state from the live player.
      setState(() {
        _position = _player.state.position;
        _duration = _player.state.duration;
        _isPlaying = _player.state.playing;
      });
    }
  }

  @override
  void didUpdateWidget(_PlaylistContent old) {
    super.didUpdateWidget(old);
    final oldTracks = _parseTracks(old.panel);
    final newTracks = _tracks;
    final oldIndex = old.panel.state['currentIndex'] as int? ?? 0;
    final newIndex = widget.panel.state['currentIndex'] as int? ?? 0;
    if (oldIndex != newIndex ||
        _trackPathAt(oldTracks, oldIndex) != _trackPathAt(newTracks, newIndex)) {
      _openCurrentTrack(autoPlay: _userInitiated);
      _userInitiated = false;
    }
  }

  String? _trackPathAt(List<Map<String, dynamic>> tracks, int idx) {
    if (tracks.isEmpty || idx >= tracks.length) return null;
    return tracks[idx]['path'] as String?;
  }

  void _subscribeToPlayer() {
    for (final s in _subs) s.cancel();
    _subs.clear();
    _subs.add(_player.stream.position.listen((p) {
      if (mounted) setState(() => _position = p);
    }));
    _subs.add(_player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    }));
    _subs.add(_player.stream.playing.listen((v) {
      if (mounted) setState(() => _isPlaying = v);
    }));
    _subs.add(_player.stream.completed.listen((completed) {
      if (completed && mounted) _onTrackCompleted();
    }));
  }

  void _openCurrentTrack({bool autoPlay = false}) {
    final tracks = _tracks;
    if (tracks.isEmpty) return;
    final idx = _currentIndex;
    if (idx >= tracks.length) return;
    final path = tracks[idx]['path'] as String? ?? '';
    final ext = _ext(path);
    final isVideo = _isVideoExt(ext);

    if (isVideo && _videoCtrl == null) {
      _videoCtrl = VideoController(_player);
    } else if (!isVideo) {
      _videoCtrl = null;
    }
    if (mounted) setState(() => _videoVisible = isVideo);
    _player.open(Media(path), play: autoPlay);
  }

  void _onTrackCompleted() {
    final tracks = _tracks;
    if (tracks.isEmpty) return;
    if (_repeat) {
      _player.seek(Duration.zero);
      _player.play();
      return;
    }
    final nextIndex = _shuffle
        ? _random.nextInt(tracks.length)
        : (_currentIndex + 1) % tracks.length;
    if (nextIndex == 0 && !_shuffle) return; // reached end, stop
    _userInitiated = true; // auto-advance counts as intentional
    _saveState(currentIndex: nextIndex);
  }

  @override
  void dispose() {
    // Cancel stream subscriptions but do NOT dispose the player —
    // PlaylistPlayerRegistry keeps it alive so music continues when the
    // user switches to another board and this widget is removed from the tree.
    for (final s in _subs) s.cancel();
    super.dispose();
  }

  // ── State persistence ──────────────────────────────────────────────────────

  void _saveState({
    List<Map<String, dynamic>>? tracks,
    int? currentIndex,
    bool? repeat,
    bool? shuffle,
  }) {
    final newState = {
      ...widget.panel.state,
      'tracks': tracks ?? _tracks,
      'currentIndex': currentIndex ?? _currentIndex,
      'repeat': repeat ?? _repeat,
      'shuffle': shuffle ?? _shuffle,
    };
    widget.renderContext.onUpdateState(newState);
  }

  // ── Track management ───────────────────────────────────────────────────────

  void _showAddMenu(BuildContext btnCtx) async {
    final colors = btnCtx.appColors;
    final box = btnCtx.findRenderObject() as RenderBox?;
    if (box == null) return;
    final pos = box.localToGlobal(Offset(0, box.size.height + 4));
    final onSurface = Theme.of(btnCtx).colorScheme.onSurface;
    final choice = await showMenu<String>(
      context: btnCtx,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 160, pos.dy + 80),
      color: colors.surfaceElevated,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      items: [
        PopupMenuItem(
          value: 'files',
          height: 36,
          child: Row(children: [
            Icon(Icons.folder_open_outlined, size: 14, color: onSurface.withAlpha(180)),
            const SizedBox(width: 8),
            Text('Add files', style: TextStyle(fontSize: 12, color: onSurface)),
          ]),
        ),
        PopupMenuItem(
          value: 'url',
          height: 36,
          child: Row(children: [
            Icon(Icons.link_rounded, size: 14, color: onSurface.withAlpha(180)),
            const SizedBox(width: 8),
            Text('Add URL', style: TextStyle(fontSize: 12, color: onSurface)),
          ]),
        ),
      ],
    );
    if (choice == 'files') {
      await _addTracks();
    } else if (choice == 'url' && mounted) {
      await _addUrl();
    }
  }

  Future<void> _addUrl() async {
    final ctrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierColor: Colors.black45,
      builder: (dctx) {
        final colors = dctx.appColors;
        final onSurface = Theme.of(dctx).colorScheme.onSurface;
        return Dialog(
          backgroundColor: colors.surfaceElevated,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Add URL', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: onSurface)),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 13, color: onSurface),
                  decoration: InputDecoration(
                    hintText: 'https://example.com/audio.mp3',
                    hintStyle: TextStyle(fontSize: 12, color: onSurface.withAlpha(100)),
                    prefixIcon: Icon(Icons.link_rounded, size: 16, color: onSurface.withAlpha(150)),
                    border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: nameCtrl,
                  style: TextStyle(fontSize: 13, color: onSurface),
                  decoration: InputDecoration(
                    hintText: 'Title (optional)',
                    hintStyle: TextStyle(fontSize: 12, color: onSurface.withAlpha(100)),
                    border: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colors.border)),
                    focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: _accent, width: 1.5)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    isDense: true,
                  ),
                  onSubmitted: (_) => Navigator.of(dctx).pop(true),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(dctx).pop(false),
                      child: Text('Cancel', style: TextStyle(fontSize: 12, color: onSurface.withAlpha(150))),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () => Navigator.of(dctx).pop(true),
                      style: FilledButton.styleFrom(backgroundColor: _accent, minimumSize: const Size(0, 32)),
                      child: const Text('Add', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    nameCtrl.dispose();
    if (confirmed != true) return;
    final url = ctrl.text.trim();
    if (url.isEmpty) return;
    final name = nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : url.split('/').last;
    final existing = _tracks;
    final track = {
      'id': '${DateTime.now().millisecondsSinceEpoch}$url',
      'path': url,
      'name': name,
      'isUrl': true,
    };
    final updated = [...existing, track];
    _saveState(tracks: updated, currentIndex: existing.isEmpty ? 0 : _currentIndex);
    if (existing.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrentTrack());
    }
  }

  Future<void> _addTracks() async {
    final result = await FilePicker.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'flac', 'aac', 'm4a', 'ogg', 'mp4', 'mov', 'avi', 'mkv', 'webm', 'm4v'],
    );
    if (result == null || result.files.isEmpty) return;
    final existing = _tracks;
    final existingPaths = existing.map((t) => t['path']).toSet();
    final newTracks = result.files
        .where((f) => f.path != null && !existingPaths.contains(f.path))
        .map((f) => {
              'id': '${DateTime.now().millisecondsSinceEpoch}${f.name}',
              'path': f.path!,
              'name': f.name,
            })
        .toList();
    if (newTracks.isEmpty) return;
    final updated = [...existing, ...newTracks];
    _saveState(
      tracks: updated,
      currentIndex: existing.isEmpty ? 0 : _currentIndex,
    );
    if (existing.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrentTrack());
    }
  }

  void _selectTrack(int index) {
    if (index == _currentIndex) {
      // Toggle play/pause on same track
      if (_isPlaying) {
        _player.pause();
      } else {
        _player.play();
      }
    } else {
      _userInitiated = true;
      _saveState(currentIndex: index);
    }
  }

  void _removeTrack(int index) {
    final tracks = List<Map<String, dynamic>>.from(_tracks);
    tracks.removeAt(index);
    int newIndex = _currentIndex;
    if (index < newIndex) newIndex--;
    if (newIndex >= tracks.length) newIndex = max(0, tracks.length - 1);
    _saveState(tracks: tracks, currentIndex: newIndex);
    if (index == _currentIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openCurrentTrack(autoPlay: false));
    }
  }

  void _skipPrev() {
    if (_position.inSeconds > 3) {
      _player.seek(Duration.zero);
      return;
    }
    final tracks = _tracks;
    if (tracks.isEmpty) return;
    final next = _shuffle
        ? _random.nextInt(tracks.length)
        : (_currentIndex - 1 + tracks.length) % tracks.length;
    _userInitiated = true;
    _saveState(currentIndex: next);
  }

  void _skipNext() {
    final tracks = _tracks;
    if (tracks.isEmpty) return;
    final next = _shuffle
        ? _random.nextInt(tracks.length)
        : (_currentIndex + 1) % tracks.length;
    _userInitiated = true;
    _saveState(currentIndex: next);
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final tracks = _tracks;
    final hasVideo = _videoVisible && _videoCtrl != null;
    final currentTrack = tracks.isNotEmpty && _currentIndex < tracks.length
        ? tracks[_currentIndex]
        : null;
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    return Column(
      children: [
        // ── Fixed top header (always visible) ─────────────────────────────
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(bottom: BorderSide(color: colors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.queue_music_rounded, size: 14, color: _accent),
              const SizedBox(width: 6),
              Text(
                '${tracks.length} track${tracks.length == 1 ? '' : 's'}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _accent),
              ),
              const Spacer(),
              Builder(
                builder: (btnCtx) => FilledButton.icon(
                  onPressed: () => _showAddMenu(btnCtx),
                  icon: const Icon(Icons.add, size: 13),
                  label: const Text('Add', style: TextStyle(fontSize: 11)),
                  style: FilledButton.styleFrom(
                    backgroundColor: _accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Media area: always 140px — video player OR audio art placeholder ─
        if (currentTrack != null)
          SizedBox(
            height: 140,
            child: hasVideo
                ? Video(controller: _videoCtrl!, controls: AdaptiveVideoControls)
                : Container(
                    color: colors.surfaceElevated,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 72,
                            height: 72,
                            decoration: BoxDecoration(
                              color: _accent.withOpacity(0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              size: 36,
                              color: _accent.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),

        // ── Now Playing bar ────────────────────────────────────────────────
        if (currentTrack != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: colors.surfaceElevated,
              border: Border(bottom: BorderSide(color: colors.border)),
            ),
            child: Column(
              children: [
                // Track name
                Text(
                  currentTrack['name'] as String? ?? '',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                // Progress slider
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: _accent,
                    inactiveTrackColor: colors.border,
                    thumbColor: _accent,
                    overlayColor: _accent.withOpacity(0.15),
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                  ),
                  child: Slider(
                    value: progress as double,
                    onChanged: (v) => _player.seek(
                      Duration(milliseconds: (v * _duration.inMilliseconds).round()),
                    ),
                  ),
                ),
                // Time
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                      Text(
                        _formatDuration(_duration),
                        style: TextStyle(
                          fontSize: 10,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                ),
                // Controls row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Shuffle
                    IconButton(
                      icon: Icon(
                        Icons.shuffle_rounded,
                        size: 18,
                        color: _shuffle ? _accent : Theme.of(context).colorScheme.onSurface.withAlpha(100),
                      ),
                      onPressed: () => _saveState(shuffle: !_shuffle),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    // Prev
                    IconButton(
                      icon: Icon(Icons.skip_previous_rounded, size: 24, color: Theme.of(context).colorScheme.onSurface),
                      onPressed: tracks.length > 1 ? _skipPrev : null,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    // Play/Pause
                    GestureDetector(
                      onTap: () => _isPlaying ? _player.pause() : _player.play(),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _accent,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                    // Next
                    IconButton(
                      icon: Icon(Icons.skip_next_rounded, size: 24, color: Theme.of(context).colorScheme.onSurface),
                      onPressed: tracks.length > 1 ? _skipNext : null,
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                    ),
                    // Repeat
                    IconButton(
                      icon: Icon(
                        Icons.repeat_rounded,
                        size: 18,
                        color: _repeat ? _accent : Theme.of(context).colorScheme.onSurface.withAlpha(100),
                      ),
                      onPressed: () => _saveState(repeat: !_repeat),
                      padding: const EdgeInsets.all(4),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              ],
            ),
          ),

        // ── Track list ─────────────────────────────────────────────────────
        Divider(height: 1, thickness: 0.5, color: colors.border),
        Expanded(
          child: tracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.queue_music_rounded, size: 40, color: _accent.withOpacity(0.35)),
                      const SizedBox(height: 8),
                      Text(
                        'No tracks yet',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.onSurface.withAlpha(120),
                        ),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: tracks.length,
                  onReorder: (oldIdx, newIdx) {
                    final updated = List<Map<String, dynamic>>.from(tracks);
                    if (newIdx > oldIdx) newIdx--;
                    final item = updated.removeAt(oldIdx);
                    updated.insert(newIdx, item);
                    int newCurrent = _currentIndex;
                    if (oldIdx == _currentIndex) {
                      newCurrent = newIdx;
                    } else if (oldIdx < _currentIndex && newIdx >= _currentIndex) {
                      newCurrent--;
                    } else if (oldIdx > _currentIndex && newIdx <= _currentIndex) {
                      newCurrent++;
                    }
                    _saveState(tracks: updated, currentIndex: newCurrent);
                  },
                  itemBuilder: (context, index) {
                    final track = tracks[index];
                    final name = track['name'] as String? ?? '';
                    final isActive = index == _currentIndex;
                    final isUrl = track['isUrl'] == true;
                    final ext = _ext(track['path'] as String? ?? '');
                    final icon = isUrl
                        ? Icons.link_rounded
                        : (_isVideoExt(ext) ? Icons.videocam_outlined : Icons.audiotrack_outlined);

                    return _TrackTile(
                      key: ValueKey(track['id']),
                      index: index,
                      name: name,
                      icon: icon,
                      isActive: isActive,
                      isPlaying: isActive && _isPlaying,
                      onTap: () => _selectTrack(index),
                      onDelete: () => _removeTrack(index),
                    );
                  },
                  buildDefaultDragHandles: false,
                ),
        ),
      ],
    );
  }
}

// ─── Track tile ───────────────────────────────────────────────────────────────

class _TrackTile extends StatefulWidget {
  const _TrackTile({
    super.key,
    required this.index,
    required this.name,
    required this.icon,
    required this.isActive,
    required this.isPlaying,
    required this.onTap,
    required this.onDelete,
  });

  final int index;
  final String name;
  final IconData icon;
  final bool isActive;
  final bool isPlaying;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_TrackTile> createState() => _TrackTileState();
}

class _TrackTileState extends State<_TrackTile> {
  static const Color _accent = Color(0xFF8B5CF6);
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 4, top: 7, bottom: 7),
          decoration: BoxDecoration(
            color: widget.isActive
                ? _accent.withOpacity(0.1)
                : (_hovered ? colors.surfaceHighlight : Colors.transparent),
            border: Border(left: BorderSide(
              color: widget.isActive ? _accent : Colors.transparent,
              width: 3,
            )),
          ),
          child: Row(
            children: [
              Icon(
                widget.isPlaying ? Icons.volume_up_rounded : widget.icon,
                size: 16,
                color: widget.isActive
                    ? _accent
                    : Theme.of(context).colorScheme.onSurface.withAlpha(120),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.name,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight:
                        widget.isActive ? FontWeight.w600 : FontWeight.normal,
                    color: widget.isActive
                        ? _accent
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // × delete button
              GestureDetector(
                onTap: widget.onDelete,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: _hovered
                        ? Colors.redAccent
                        : Theme.of(context).colorScheme.onSurface.withAlpha(60),
                  ),
                ),
              ),
              // ≡ drag handle
              ReorderableDragStartListener(
                index: widget.index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Icon(
                    Icons.drag_handle_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(80),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
