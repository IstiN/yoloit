import 'dart:async';

import 'package:js_widget_runtime/js_widget_runtime.dart';
import 'package:media_kit/media_kit.dart';

/// yoloit implementation of [JsAudioController] backed by `media_kit`.
class MediaKitAudioController extends JsAudioController {
  MediaKitAudioController._(this._player);

  final Player _player;
  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final List<StreamSubscription<dynamic>> _subs = [];

  static Future<MediaKitAudioController> create(String src) async {
    final player = Player();
    final instance = MediaKitAudioController._(player);
    instance._subs.addAll([
      player.stream.position.listen(instance._position.add),
      player.stream.duration.listen(instance._duration.add),
      player.stream.playing.listen(instance._playing.add),
    ]);
    await player.open(Media(src));
    return instance;
  }

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
    await _player.dispose();
  }

  /// Returns a [JsAudioController] that initializes itself asynchronously.
  static JsAudioController async(String src) => _AsyncAudioController(src);
}

/// Wraps async audio controller creation.
class _AsyncAudioController extends JsAudioController {
  _AsyncAudioController(this.src) {
    _future = MediaKitAudioController.create(src);
    _future.then((c) {
      _delegate = c;
      _ready.complete();
    });
  }

  final String src;
  late final Future<MediaKitAudioController> _future;
  MediaKitAudioController? _delegate;
  final _ready = Completer<void>();

  MediaKitAudioController get _require {
    final d = _delegate;
    if (d == null) throw StateError('Audio controller not ready');
    return d;
  }

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
}
