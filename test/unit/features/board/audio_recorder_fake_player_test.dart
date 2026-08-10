// covers-write: board.audio_recorder

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_content_vm.dart';
import 'package:yoloit/features/board/plugins/builtin/audio_recorder_plugin.dart';

/// Fake [Player] that does not require libmpv. All stream controllers are
/// broadcast so listeners can be added at any time. Unimplemented members
/// throw via [noSuchMethod] so unexpected calls are visible.
class _FakePlayer implements Player {
  _FakePlayer();

  PlayerState _state = const PlayerState();

  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final completedCtl = StreamController<bool>.broadcast();

  final List<String> opened = [];
  final List<String> paused = [];
  final List<String> played = [];
  bool disposed = false;

  @override
  PlayerState get state => _state;
  set state(PlayerState value) => _state = value;

  @override
  PlayerStream get stream => _FakePlayerStream(this);

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
  }

  @override
  Future<void> pause() async {
    paused.add('pause');
  }

  @override
  Future<void> play() async {
    played.add('play');
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await positionCtl.close();
    await durationCtl.close();
    await playingCtl.close();
    await completedCtl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

class _FakePlayerStream implements PlayerStream {
  const _FakePlayerStream(this._player);

  final _FakePlayer _player;

  @override
  Stream<Duration> get position => _player.positionCtl.stream;

  @override
  Stream<Duration> get duration => _player.durationCtl.stream;

  @override
  Stream<bool> get playing => _player.playingCtl.stream;

  @override
  Stream<bool> get completed => _player.completedCtl.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

BoardPanelInstance _panel({Map<String, dynamic>? state}) => BoardPanelInstance(
      id: 'panel-audio-fake',
      type: AudioRecorderPlugin.kTypeId,
      title: 'Audio Recorder',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 380, height: 460),
      state: state ?? const AudioRecorderPlugin().initialState,
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(body: SizedBox(width: 380, height: 460, child: child)),
    );

Map<String, dynamic> _stateWith(Map<String, dynamic> patch) =>
    <String, dynamic>{...const AudioRecorderPlugin().initialState, ...patch};

Map<String, dynamic> _rec(
  String name, {
  String? path,
  String id = 'rec-1',
}) => <String, dynamic>{
  'id': id,
  'path': path ?? '/nonexistent/$name',
  'name': name,
  'durationMs': 1234,
  'sizeBytes': 0,
  'createdAt': 0,
  'format': 'wav',
};

void main() {
  group('_ensurePlayer with fake Player', () {
    late _FakePlayer fakePlayer;

    setUp(() {
      fakePlayer = _FakePlayer();
      AudioRecorderPanelContent.debugPlayerFactory = () => fakePlayer;
    });

    tearDown(() {
      AudioRecorderPanelContent.debugPlayerFactory = null;
    });

    testWidgets('_togglePlay opens media for a new recording id', (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('clip.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // _ensurePlayer created the fake player and _togglePlay called open().
      expect(fakePlayer.opened, ['/nonexistent/clip.wav']);
    });

    testWidgets('_togglePlay pauses when same recording is already playing',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('clip.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // First tap: open media.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(fakePlayer.opened, hasLength(1));

      // Simulate playing state from the player stream.
      fakePlayer.playingCtl.add(true);
      await tester.pump();

      // Second tap: same id + isPlaying → pause() path.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(fakePlayer.paused, hasLength(1));
    });

    testWidgets('_togglePlay resumes with play() when same id but not playing',
        (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('clip.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // First tap: open media → sets _playingId.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Simulate paused state (playing = false).
      fakePlayer.playingCtl.add(false);
      await tester.pump();

      // Second tap: same id + NOT playing → play() resume path.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      expect(fakePlayer.played, hasLength(1));
    });

    testWidgets('_ensurePlayer subscribes to player streams', (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('clip.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // Trigger _ensurePlayer by tapping play.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Emit stream events — the subscriptions update state via setState.
      fakePlayer.positionCtl.add(const Duration(seconds: 5));
      fakePlayer.durationCtl.add(const Duration(seconds: 30));
      fakePlayer.playingCtl.add(true);
      fakePlayer.completedCtl.add(true);
      await tester.pump();

      // After completed=true, _isPlaying resets to false and position resets.
      // The widget rebuilds without error.
      expect(find.byType(AudioRecorderPanelContent), findsOneWidget);
    });

    testWidgets('_togglePlay switches to a new recording id', (tester) async {
      Map<String, dynamic>? written;
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (state) => written = state,
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[
                  _rec('a.wav', id: 'rec-a'),
                  _rec('b.wav', id: 'rec-b'),
                ],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // Tap first recording.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-a.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(fakePlayer.opened, ['/nonexistent/a.wav']);

      // Tap second recording — _playingId != id → open new media.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-b.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(fakePlayer.opened, ['/nonexistent/a.wav', '/nonexistent/b.wav']);
    });

    testWidgets('_ensurePlayer returns cached player on second call',
        (tester) async {
      final renderContext = BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onUpdateState: (_) {},
        onShowEditor: () {},
      );

      await tester.pumpWidget(
        _wrap(
          AudioRecorderPanelContent(
            panel: _panel(
              state: _stateWith(<String, dynamic>{
                'recordings': <Map<String, dynamic>>[_rec('clip.wav')],
              }),
            ),
            renderContext: renderContext,
          ),
        ),
      );

      // First tap creates the player via _ensurePlayer.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Second tap uses the cached player (no new open since same id).
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('play-clip.wav')));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();

      // Only one open call (from the first tap); the second tap hits the
      // _playingId == id && !_isPlaying → play() branch.
      expect(fakePlayer.opened, hasLength(1));
      expect(fakePlayer.played, hasLength(1));
    });
  });
}
