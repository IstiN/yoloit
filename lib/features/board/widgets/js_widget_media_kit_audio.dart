import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Host-provided custom builder for the `audio` node in the JSON widget tree.
///
/// Props:
/// - `src` (String, required): file path or URL.
/// - `autoPlay` (bool, default false).
/// - `loop` (bool, default false).
/// - `title` (String): optional label shown above the controls.
Widget buildMediaKitAudio(BuildContext context, Map<String, dynamic> m) {
  final src = m['src'] as String?;
  if (src == null || src.isEmpty) {
    return const Center(child: Icon(Icons.audiotrack_outlined));
  }
  return _MediaKitAudioPlayer(
    src: src,
    autoPlay: m['autoPlay'] == true,
    loop: m['loop'] == true,
    title: m['title'] as String?,
  );
}

class _MediaKitAudioPlayer extends StatefulWidget {
  const _MediaKitAudioPlayer({
    required this.src,
    required this.autoPlay,
    required this.loop,
    this.title,
  });

  final String src;
  final bool autoPlay;
  final bool loop;
  final String? title;

  @override
  State<_MediaKitAudioPlayer> createState() => _MediaKitAudioPlayerState();
}

class _MediaKitAudioPlayerState extends State<_MediaKitAudioPlayer> {
  late final Player _player;
  final List<StreamSubscription<dynamic>> _subs = [];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _subs.addAll([
      _player.stream.position.listen((p) => setState(() => _position = p)),
      _player.stream.duration.listen((d) => setState(() => _duration = d)),
      _player.stream.playing.listen((p) => setState(() => _isPlaying = p)),
    ]);
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    await _player.open(Media(widget.src));
    if (widget.loop) {
      await _player.setPlaylistMode(PlaylistMode.loop);
    }
    if (widget.autoPlay) {
      await _player.play();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    unawaited(_player.dispose());
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      await _player.play();
    }
  }

  Future<void> _seek(double value) async {
    if (_duration.inMilliseconds > 0) {
      final target = Duration(
        milliseconds: (value * _duration.inMilliseconds).round(),
      );
      await _player.seek(target);
    }
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final progress = _duration.inMilliseconds > 0
        ? (_position.inMilliseconds / _duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                widget.title!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Row(
            children: [
              IconButton(
                onPressed: _toggle,
                icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
              ),
              Expanded(
                child: Slider(
                  value: progress.toDouble(),
                  onChanged: _seek,
                ),
              ),
              SizedBox(
                width: 72,
                child: Text(
                  '${_format(_position)} / ${_format(_duration)}',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
