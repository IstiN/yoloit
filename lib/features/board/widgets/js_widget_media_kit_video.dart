import 'dart:async';

import 'package:flutter/material.dart';
import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

/// yoloit implementation of [JsVideoController] backed by `media_kit`.
class MediaKitVideoController extends JsVideoController {
  MediaKitVideoController._(this._player, this._controller);

  final Player _player;
  final VideoController _controller;
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _aspectRatio = StreamController<double?>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Creates a fully initialized controller.
  static Future<MediaKitVideoController> create(String src) async {
    final player = Player();
    final controller = VideoController(player);
    final instance = MediaKitVideoController._(player, controller);
    instance._subs.addAll([
      player.stream.position.listen(instance._position.add),
      player.stream.duration.listen(instance._duration.add),
      player.stream.playing.listen(instance._playing.add),
      player.stream.videoParams.listen((params) {
        final w = params.w;
        final h = params.h;
        if (w != null && h != null && h != 0) {
          instance._aspectRatio.add(w / h);
        }
      }),
    ]);
    await player.open(Media(src));
    return instance;
  }

  @override
  double? get aspectRatio {
    final params = _player.state.videoParams;
    final w = params.w;
    final h = params.h;
    if (w != null && h != null && h != 0) return w / h;
    return null;
  }

  @override
  Stream<double?> get aspectRatioStream => _aspectRatio.stream;

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> dispose() async {
    for (final sub in _subs) {
      await sub.cancel();
    }
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _aspectRatio.close();
    await _player.dispose();
  }

  @override
  Widget buildVideo(
    BuildContext context, {
    BoxFit fit = BoxFit.contain,
    double? width,
    double? height,
  }) =>
      Video(
        controller: _controller,
        fit: fit,
        width: width,
        height: height,
      );

  /// Returns a [JsVideoController] that initializes itself asynchronously.
  static JsVideoController async(String src) => _AsyncVideoController(src);
}

/// Wraps async controller creation so [JsVideoWidget] gets a controller
/// immediately and can await initialization internally.
class _AsyncVideoController extends JsVideoController {
  _AsyncVideoController(this.src) {
    _future = MediaKitVideoController.create(src);
    _future.then((c) {
      _delegate = c;
      _ready.complete();
    });
  }

  final String src;
  late final Future<MediaKitVideoController> _future;
  MediaKitVideoController? _delegate;
  final _ready = Completer<void>();

  MediaKitVideoController get _require {
    final d = _delegate;
    if (d == null) throw StateError('Video controller not ready');
    return d;
  }

  @override
  double? get aspectRatio => _delegate?.aspectRatio;

  @override
  Stream<double?> get aspectRatioStream => _delegate?.aspectRatioStream ??
      _future.asStream().asyncExpand((c) => c.aspectRatioStream);

  @override
  Stream<Duration> get positionStream => _delegate?.positionStream ??
      _future.asStream().asyncExpand((c) => c.positionStream);

  @override
  Stream<Duration> get durationStream => _delegate?.durationStream ??
      _future.asStream().asyncExpand((c) => c.durationStream);

  @override
  Stream<bool> get playingStream => _delegate?.playingStream ??
      _future.asStream().asyncExpand((c) => c.playingStream);

  @override
  Future<void> play() async {
    await _ready.future;
    return _require.play();
  }

  @override
  Future<void> pause() async {
    await _ready.future;
    return _require.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _ready.future;
    return _require.seek(position);
  }

  @override
  Future<void> dispose() async {
    if (_delegate != null) return _require.dispose();
    _future.ignore();
  }

  @override
  Widget buildVideo(
    BuildContext context, {
    BoxFit fit = BoxFit.contain,
    double? width,
    double? height,
  }) {
    final delegate = _delegate;
    if (delegate != null) {
      return delegate.buildVideo(
        context,
        fit: fit,
        width: width,
        height: height,
      );
    }
    return FutureBuilder<MediaKitVideoController>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting ||
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return snapshot.data!.buildVideo(
          context,
          fit: fit,
          width: width,
          height: height,
        );
      },
    );
  }
}
