import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// Host-provided custom builder for the `video` node in the JSON widget tree.
///
/// Props:
/// - `src` (String, required): file path or URL.
/// - `autoPlay` (bool, default false).
/// - `loop` (bool, default false).
/// - `controls` (bool, default true).
/// - `fit` (`cover`/`contain`/`fill`/`fitWidth`/`fitHeight`/`none`, default `contain`).
/// - `width` / `height`: optional explicit size.
Widget buildMediaKitVideo(BuildContext context, Map<String, dynamic> m) {
  final src = m['src'] as String?;
  if (src == null || src.isEmpty) {
    return const Center(child: Icon(Icons.videocam_off_outlined));
  }
  return _MediaKitVideoPlayer(
    src: src,
    autoPlay: m['autoPlay'] == true,
    loop: m['loop'] == true,
    controls: m['controls'] != false,
    fit: _parseBoxFit(m['fit'] as String?),
    width: _doubleOrNull(m['width']),
    height: _doubleOrNull(m['height']),
  );
}

class _MediaKitVideoPlayer extends StatefulWidget {
  const _MediaKitVideoPlayer({
    required this.src,
    required this.autoPlay,
    required this.loop,
    required this.controls,
    required this.fit,
    this.width,
    this.height,
  });

  final String src;
  final bool autoPlay;
  final bool loop;
  final bool controls;
  final BoxFit fit;
  final double? width;
  final double? height;

  @override
  State<_MediaKitVideoPlayer> createState() => _MediaKitVideoPlayerState();
}

class _MediaKitVideoPlayerState extends State<_MediaKitVideoPlayer> {
  late final Player _player;
  late final VideoController _controller;

  @override
  void initState() {
    super.initState();
    _player = Player();
    _controller = VideoController(_player);
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
    unawaited(_player.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final video = Video(
      controller: _controller,
      controls: (widget.controls
          ? AdaptiveVideoControls
          : NoVideoControls) as VideoControlsBuilder?,
      fit: widget.fit,
      width: widget.width,
      height: widget.height,
    );
    if (widget.width != null || widget.height != null) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: video,
      );
    }
    return video;
  }
}

BoxFit _parseBoxFit(String? value) => switch (value) {
  'cover' => BoxFit.cover,
  'contain' => BoxFit.contain,
  'fill' => BoxFit.fill,
  'fitWidth' => BoxFit.fitWidth,
  'fitHeight' => BoxFit.fitHeight,
  'none' => BoxFit.none,
  _ => BoxFit.contain,
};

double? _doubleOrNull(dynamic v) => v == null ? null : (v as num).toDouble();
