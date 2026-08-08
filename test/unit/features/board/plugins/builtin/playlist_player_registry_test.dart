import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_player_registry_vm.dart';

void main() {
  group('PlaylistPlayerRegistry.applyPlaybackCommand', () {
    late _FakePlayer fake;
    late int factoryCalls;
    const panelId = 'playlist-registry-test';

    setUp(() {
      fake = _FakePlayer();
      factoryCalls = 0;
      PlaylistPlayerRegistry.debugPlayerFactory = () {
        factoryCalls++;
        return fake;
      };
    });

    tearDown(() {
      PlaylistPlayerRegistry.debugPlayerFactory = null;
      PlaylistPlayerRegistry.instance.release(panelId);
    });

    Map<String, dynamic> state({
      bool playing = false,
      int currentIndex = 0,
      List<Map<String, dynamic>>? tracks,
    }) =>
        <String, dynamic>{
          'tracks': tracks ??
              <Map<String, dynamic>>[
                {'id': 't1', 'path': '/music/alpha.mp3', 'name': 'Alpha'},
                {'id': 't2', 'path': '/music/beta.mp3', 'name': 'Beta'},
              ],
          'currentIndex': currentIndex,
          'playing': playing,
        };

    test('returns immediately when the playlist has no tracks', () async {
      await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
        panelId,
        state(playing: true, tracks: const []),
      );

      // No player was even acquired.
      expect(factoryCalls, 0);
      expect(fake.opened, isEmpty);
    });

    test('opens the current track with autoplay when playing is requested',
        () async {
      await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
        panelId,
        state(playing: true, currentIndex: 1),
      );

      expect(fake.opened, hasLength(1));
      expect(fake.opened.single.uri, '/music/beta.mp3');
      expect(fake.opened.single.play, isTrue);
      expect(PlaylistPlayerRegistry.instance.isPlaying(panelId), isTrue);
    });

    test('does nothing when the same track is already playing', () async {
      final registry = PlaylistPlayerRegistry.instance;
      await registry.applyPlaybackCommand(panelId, state(playing: true));
      await registry.applyPlaybackCommand(panelId, state(playing: true));

      // No re-open, no extra play call.
      expect(fake.opened, hasLength(1));
      expect(fake.playCalls, 0);
    });

    test('resumes a paused player for the same track instead of reopening',
        () async {
      final registry = PlaylistPlayerRegistry.instance;
      await registry.applyPlaybackCommand(panelId, state(playing: true));
      await registry.applyPlaybackCommand(panelId, state(playing: false));
      expect(fake.pauseCalls, 1);

      await registry.applyPlaybackCommand(panelId, state(playing: true));

      expect(fake.playCalls, 1);
      expect(fake.opened, hasLength(1));
    });

    test('opens a different track when the index changes', () async {
      final registry = PlaylistPlayerRegistry.instance;
      await registry.applyPlaybackCommand(panelId, state(playing: true));
      await registry.applyPlaybackCommand(
        panelId,
        state(playing: true, currentIndex: 1),
      );

      expect(fake.opened, hasLength(2));
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isTrue);
    });

    test('pauses when playback is not requested and the player is playing',
        () async {
      final registry = PlaylistPlayerRegistry.instance;
      await registry.applyPlaybackCommand(panelId, state(playing: true));
      await registry.applyPlaybackCommand(panelId, state(playing: false));

      expect(fake.pauseCalls, 1);
      expect(PlaylistPlayerRegistry.instance.isPlaying(panelId), isFalse);
    });

    test('does nothing when paused and playback is not requested', () async {
      await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
        panelId,
        state(playing: false),
      );

      expect(fake.opened, isEmpty);
      expect(fake.pauseCalls, 0);
    });

    test('returns without opening when the current track has an empty path',
        () async {
      await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
        panelId,
        state(
          playing: true,
          tracks: const [
            {'id': 't1', 'path': '', 'name': 'Empty'},
          ],
        ),
      );

      // Player was acquired but nothing was opened.
      expect(factoryCalls, 1);
      expect(fake.opened, isEmpty);
    });

    test('clamps an out-of-range current index to the last track', () async {
      await PlaylistPlayerRegistry.instance.applyPlaybackCommand(
        panelId,
        state(playing: true, currentIndex: 99),
      );

      expect(fake.opened.single.uri, '/music/beta.mp3');
    });
  });
}

/// In-memory [Player] replacement: the real media_kit player needs native
/// libmpv, which is unavailable in unit tests. Unimplemented members throw
/// via [noSuchMethod], so unexpected usage fails loudly.
class _FakePlayer implements Player {
  PlayerState _state = const PlayerState();

  final List<({String uri, bool play})> opened = [];
  int playCalls = 0;
  int pauseCalls = 0;

  @override
  PlayerState get state => _state;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((uri: (playable as Media).uri, play: play));
    _state = _state.copyWith(playing: play);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _state = _state.copyWith(playing: true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _state = _state.copyWith(playing: false);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
