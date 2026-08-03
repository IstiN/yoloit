import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/board_plugin.dart';
import 'package:yoloit/features/board/plugins/builtin/playlist_plugin.dart';
import 'package:yoloit/features/board/ui/board_file_picker.dart';

void main() {
  group('reorderPlaylistTracks', () {
    final tracks = [
      {'id': 'a', 'path': '/a.mp3', 'name': 'A'},
      {'id': 'b', 'path': '/b.mp3', 'name': 'B'},
      {'id': 'c', 'path': '/c.mp3', 'name': 'C'},
    ];

    test('moves the current track and follows it with the index', () {
      final result = reorderPlaylistTracks(tracks, 1, 1, 3);
      expect(result.tracks.map((t) => t['id']), ['a', 'c', 'b']);
      expect(result.currentIndex, 2);
    });

    test('decrements index when an earlier track moves past current', () {
      final result = reorderPlaylistTracks(tracks, 2, 0, 3);
      expect(result.tracks.map((t) => t['id']), ['b', 'c', 'a']);
      expect(result.currentIndex, 1);
    });

    test('increments index when a later track moves before current', () {
      final result = reorderPlaylistTracks(tracks, 0, 2, 0);
      expect(result.tracks.map((t) => t['id']), ['c', 'a', 'b']);
      expect(result.currentIndex, 1);
    });

    test('keeps index when the move does not cross the current track', () {
      final result = reorderPlaylistTracks(tracks, 0, 1, 3);
      expect(result.tracks.map((t) => t['id']), ['a', 'c', 'b']);
      expect(result.currentIndex, 0);
    });
  });

  group('newPlaylistTracksFromPicks', () {
    test('builds entries for new files and skips existing paths', () {
      final existing = [
        {'id': 'a', 'path': '/music/a.mp3', 'name': 'a.mp3'},
      ];
      final result = newPlaylistTracksFromPicks(existing, const [
        BoardFileSelection(path: '/music/a.mp3', name: 'a.mp3'),
        BoardFileSelection(path: '/music/b.mp3', name: 'b.mp3'),
      ]);
      expect(result, hasLength(1));
      expect(result.single['path'], '/music/b.mp3');
      expect(result.single['name'], 'b.mp3');
      expect(result.single['id'], isA<String>());
    });
  });

  group('playlist panel', () {
    late _FakePlayer fake;

    setUp(() {
      fake = _FakePlayer();
      debugPlaylistPlayerFactory = (_) => fake;
    });

    tearDown(() {
      debugPlaylistPlayerFactory = null;
      unawaited(fake.close());
    });

    testWidgets('renders tracks and opens the current track paused', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      expect(find.text('2 tracks'), findsOneWidget);
      expect(find.text('Alpha'), findsWidgets);
      expect(find.text('Beta'), findsOneWidget);
      expect(fake.opened, hasLength(1));
      expect(fake.opened.single.uri, '/music/alpha.mp3');
      expect(fake.opened.single.play, isFalse);
      // Audio placeholder art is shown instead of a video surface.
      expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    });

    testWidgets('empty playlist shows the placeholder', (tester) async {
      final harness = _PlaylistHarness(_emptyState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      expect(find.text('0 tracks'), findsOneWidget);
      expect(find.text('No tracks yet'), findsOneWidget);
      expect(fake.opened, isEmpty);
    });

    testWidgets('position and duration streams drive the progress texts', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.durationCtrl.add(const Duration(seconds: 100));
      await _pumpOut(tester);
      fake.positionCtrl.add(const Duration(seconds: 30));
      await _pumpOut(tester);

      expect(find.text('00:30'), findsOneWidget);
      expect(find.text('01:40'), findsOneWidget);

      fake.durationCtrl.add(const Duration(seconds: 3725));
      await _pumpOut(tester);
      expect(find.text('1:02:05'), findsOneWidget);
    });

    testWidgets('play/pause button toggles the player', (tester) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byIcon(Icons.play_arrow_rounded));
      await _pumpOut(tester);
      expect(fake.playCalls, 1);

      await tester.tap(find.byIcon(Icons.pause_rounded));
      await _pumpOut(tester);
      expect(fake.pauseCalls, 1);
    });

    testWidgets('shuffle and repeat toggles persist to panel state', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await _pumpOut(tester);
      expect(harness.state['shuffle'], isTrue);

      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await _pumpOut(tester);
      expect(harness.state['repeat'], isTrue);
    });

    testWidgets('skip next advances and reopens the track with autoplay', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await _pumpOut(tester);

      expect(harness.state['currentIndex'], 1);
      expect(fake.opened, hasLength(2));
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isTrue);
    });

    testWidgets('skip previous seeks to start when past 3 seconds', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.positionCtrl.add(const Duration(seconds: 10));
      await _pumpOut(tester);
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await _pumpOut(tester);

      expect(fake.seeks, contains(Duration.zero));
      expect(harness.state['currentIndex'], 0);
    });

    testWidgets('skip previous wraps to the last track near the start', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.positionCtrl.add(const Duration(seconds: 1));
      await _pumpOut(tester);
      await tester.tap(find.byIcon(Icons.skip_previous_rounded));
      await _pumpOut(tester);

      expect(harness.state['currentIndex'], 1);
      expect(fake.opened.last.uri, '/music/beta.mp3');
    });

    testWidgets('selecting a track opens it; selecting current toggles play', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.widgetWithText(GestureDetector, 'Beta'));
      await _pumpOut(tester);
      expect(harness.state['currentIndex'], 1);
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isTrue);

      // Tapping the now-current track toggles playback.
      await tester.tap(find.widgetWithText(GestureDetector, 'Beta'));
      await _pumpOut(tester);
      expect(fake.playCalls, 1);
    });

    testWidgets('removing the current track reopens the next one paused', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byIcon(Icons.close_rounded).first);
      await _pumpOut(tester);

      final tracks = (harness.state['tracks'] as List).cast<Map<String, dynamic>>();
      expect(tracks, hasLength(1));
      expect(tracks.single['name'], 'Beta');
      expect(harness.state['currentIndex'], 0);
      // Reopened paused — once via didUpdateWidget and once via the
      // post-frame callback in _removeTrack.
      expect(fake.opened.length, greaterThanOrEqualTo(2));
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isFalse);
    });

    testWidgets('removing a later track keeps the current index', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.byIcon(Icons.close_rounded).last);
      await _pumpOut(tester);

      final tracks = (harness.state['tracks'] as List).cast<Map<String, dynamic>>();
      expect(tracks, hasLength(1));
      expect(tracks.single['name'], 'Alpha');
      expect(harness.state['currentIndex'], 0);
      // No extra open for a non-current removal.
      expect(fake.opened, hasLength(1));
    });

    testWidgets('reordering via drag keeps the current track selected', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_threeTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.drag(
        find.byIcon(Icons.drag_handle_rounded).first,
        const Offset(0, 40),
      );
      await _pumpOut(tester);

      expect(harness.updates, isNotEmpty);
      final tracks =
          (harness.updates.last['tracks'] as List).cast<Map<String, dynamic>>();
      final alphaPos = tracks.indexWhere((t) => t['name'] == 'Alpha');
      expect(alphaPos, greaterThan(0));
      expect(harness.updates.last['currentIndex'], alphaPos);
    });

    testWidgets('track completion advances to the next track', (tester) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.completedCtrl.add(true);
      await _pumpOut(tester);

      expect(harness.state['currentIndex'], 1);
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isTrue);
    });

    testWidgets('track completion at the end of the list stops', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState()..['currentIndex'] = 1);
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);
      final updatesBefore = harness.updates.length;

      fake.completedCtrl.add(true);
      await _pumpOut(tester);

      expect(harness.updates, hasLength(updatesBefore));
      expect(harness.state['currentIndex'], 1);
    });

    testWidgets('repeat replays the current track on completion', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState()..['repeat'] = true);
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.completedCtrl.add(true);
      await _pumpOut(tester);

      expect(fake.seeks, contains(Duration.zero));
      expect(fake.playCalls, 1);
      expect(harness.state['currentIndex'], 0);
    });

    testWidgets('shuffle picks a random track on completion', (tester) async {
      final harness = _PlaylistHarness(_threeTracksState()..['shuffle'] = true);
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      fake.completedCtrl.add(true);
      await _pumpOut(tester);

      expect(harness.updates, isNotEmpty);
      final next = harness.updates.last['currentIndex'] as int;
      expect(next, inInclusiveRange(0, 2));
    });

    testWidgets('external playing flag toggles playback on the same track', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      final key = GlobalKey<_PlaylistHostState>();
      await tester.pumpWidget(_playlistApp(harness, hostKey: key));
      await _pumpOut(tester);

      key.currentState!.applyState({'playing': true});
      await _pumpOut(tester);
      expect(fake.playCalls, 1);
      // Same track — no re-open.
      expect(fake.opened, hasLength(1));

      key.currentState!.applyState({'playing': false});
      await _pumpOut(tester);
      expect(fake.pauseCalls, 1);
    });

    testWidgets('external index change reopens without autoplay', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      final key = GlobalKey<_PlaylistHostState>();
      await tester.pumpWidget(_playlistApp(harness, hostKey: key));
      await _pumpOut(tester);

      key.currentState!.applyState({'currentIndex': 1});
      await _pumpOut(tester);

      expect(fake.opened, hasLength(2));
      expect(fake.opened.last.uri, '/music/beta.mp3');
      expect(fake.opened.last.play, isFalse);
    });

    testWidgets('add menu offers file and URL sources', (tester) async {
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.text('Add files'), findsOneWidget);
      expect(find.text('Add URL'), findsOneWidget);

      // Picking "Add files" with a cancelled picker dismisses the menu and
      // leaves the playlist unchanged.
      final updatesBefore = harness.updates.length;
      await tester.tap(find.text('Add files'));
      await tester.pumpAndSettle();
      expect(find.text('Add files'), findsNothing);
      expect(harness.updates, hasLength(updatesBefore));
      expect((harness.state['tracks'] as List), hasLength(2));
    });

    testWidgets('add URL appends a named URL track', (tester) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.text('Add'));
      await _pumpOut(tester);
      await tester.tap(find.text('Add URL'));
      await _pumpOut(tester);

      final fields = find.byType(TextField);
      await tester.enterText(fields.first, 'https://example.com/song.mp3');
      await tester.enterText(fields.last, 'Song');
      await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
      await _pumpOut(tester);

      final tracks =
          (harness.state['tracks'] as List).cast<Map<String, dynamic>>();
      expect(tracks, hasLength(3));
      expect(tracks.last['path'], 'https://example.com/song.mp3');
      expect(tracks.last['name'], 'Song');
      expect(tracks.last['isUrl'], isTrue);
    });

    testWidgets('add URL derives the name from the URL when omitted', (
      tester,
    ) async {
      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.text('Add'));
      await _pumpOut(tester);
      await tester.tap(find.text('Add URL'));
      await _pumpOut(tester);

      await tester.enterText(
        find.byType(TextField).first,
        'https://example.com/clip.mp3',
      );
      await tester.tap(find.widgetWithText(FilledButton, 'Add').last);
      await _pumpOut(tester);

      final tracks =
          (harness.state['tracks'] as List).cast<Map<String, dynamic>>();
      expect(tracks.last['name'], 'clip.mp3');
    });

    testWidgets('add files merges new picks and skips duplicates', (
      tester,
    ) async {
      const channel = MethodChannel('miguelruivo.flutter.plugins.filepicker');
      Future<Object?> handler(MethodCall call) async {
        if (call.method == 'any') {
          return [
            {'name': 'gamma.mp3', 'path': '/music/gamma.mp3', 'size': 10},
            // Duplicate of an existing track — must be skipped.
            {'name': 'alpha.mp3', 'path': '/music/alpha.mp3', 'size': 10},
          ];
        }
        return null;
      }

      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        handler,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );

      final harness = _PlaylistHarness(_twoTracksState());
      await tester.pumpWidget(_playlistApp(harness));
      await _pumpOut(tester);

      await tester.tap(find.text('Add'));
      await _pumpOut(tester);
      await tester.tap(find.text('Add files'));
      await _pumpOut(tester);

      final tracks =
          (harness.state['tracks'] as List).cast<Map<String, dynamic>>();
      expect(tracks, hasLength(3));
      expect(tracks.map((t) => t['name']), contains('gamma.mp3'));
      // The duplicate path was skipped — only the original entry remains.
      expect(
        tracks.where((t) => t['path'] == '/music/alpha.mp3'),
        hasLength(1),
      );
      expect(harness.state['currentIndex'], 0);
    });
  });
}

// ── Fake player ─────────────────────────────────────────────────────────────

/// In-memory [Player] replacement: the real media_kit player needs native
/// libmpv, which is unavailable in widget tests. Unimplemented members throw
/// via [noSuchMethod], so unexpected usage fails loudly.
class _FakePlayer implements Player {
  PlayerState _state = const PlayerState();

  final StreamController<bool> playingCtrl = StreamController<bool>.broadcast();
  final StreamController<bool> completedCtrl =
      StreamController<bool>.broadcast();
  final StreamController<Duration> positionCtrl =
      StreamController<Duration>.broadcast();
  final StreamController<Duration> durationCtrl =
      StreamController<Duration>.broadcast();

  final List<({String uri, bool play})> opened = [];
  final List<Duration> seeks = [];
  int playCalls = 0;
  int pauseCalls = 0;

  Future<void> close() async {
    await playingCtrl.close();
    await completedCtrl.close();
    await positionCtrl.close();
    await durationCtrl.close();
  }

  @override
  PlayerState get state => _state;

  @override
  PlayerStream get stream => PlayerStream(
    const Stream<Playlist>.empty(),
    playingCtrl.stream,
    completedCtrl.stream,
    positionCtrl.stream,
    durationCtrl.stream,
    const Stream<double>.empty(),
    const Stream<double>.empty(),
    const Stream<double>.empty(),
    const Stream<bool>.empty(),
    const Stream<double>.empty(),
    const Stream<Duration>.empty(),
    const Stream<PlaylistMode>.empty(),
    const Stream<bool>.empty(),
    const Stream<AudioParams>.empty(),
    const Stream<VideoParams>.empty(),
    const Stream<double?>.empty(),
    const Stream<AudioDevice>.empty(),
    const Stream<List<AudioDevice>>.empty(),
    const Stream<Track>.empty(),
    const Stream<Tracks>.empty(),
    const Stream<int?>.empty(),
    const Stream<int?>.empty(),
    const Stream<List<String>>.empty(),
    const Stream<PlayerLog>.empty(),
    const Stream<String>.empty(),
  );

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((uri: (playable as Media).uri, play: play));
    _state = _state.copyWith(playing: play);
  }

  @override
  Future<void> play() async {
    playCalls++;
    _state = _state.copyWith(playing: true);
    playingCtrl.add(true);
  }

  @override
  Future<void> pause() async {
    pauseCalls++;
    _state = _state.copyWith(playing: false);
    playingCtrl.add(false);
  }

  @override
  Future<void> seek(Duration duration) async {
    seeks.add(duration);
    _state = _state.copyWith(position: duration);
  }

  @override
  Future<void> dispose() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ── Harness ─────────────────────────────────────────────────────────────────

class _PlaylistHarness {
  _PlaylistHarness(this.state);

  Map<String, dynamic> state;
  final List<Map<String, dynamic>> updates = [];
}

Map<String, dynamic> _emptyState() => {
  'tracks': <Map<String, dynamic>>[],
  'currentIndex': 0,
  'repeat': false,
  'shuffle': false,
};

Map<String, dynamic> _twoTracksState() => {
  'tracks': [
    {'id': 't1', 'path': '/music/alpha.mp3', 'name': 'Alpha'},
    {'id': 't2', 'path': '/music/beta.mp3', 'name': 'Beta'},
  ],
  'currentIndex': 0,
  'repeat': false,
  'shuffle': false,
};

Map<String, dynamic> _threeTracksState() => {
  'tracks': [
    {'id': 't1', 'path': '/music/alpha.mp3', 'name': 'Alpha'},
    {'id': 't2', 'path': '/music/beta.mp3', 'name': 'Beta'},
    {'id': 't3', 'path': '/music/gamma.mp3', 'name': 'Gamma'},
  ],
  'currentIndex': 0,
  'repeat': false,
  'shuffle': false,
};

Widget _playlistApp(_PlaylistHarness harness, {GlobalKey? hostKey}) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 380,
        height: 520,
        child: _PlaylistHost(
          key: hostKey,
          harness: harness,
        ),
      ),
    ),
  );
}

class _PlaylistHost extends StatefulWidget {
  const _PlaylistHost({super.key, required this.harness});

  final _PlaylistHarness harness;

  @override
  State<_PlaylistHost> createState() => _PlaylistHostState();
}

class _PlaylistHostState extends State<_PlaylistHost> {
  /// Applies an external state patch (simulates CLI/other-panel updates).
  void applyState(Map<String, dynamic> patch) {
    setState(() => widget.harness.state = {...widget.harness.state, ...patch});
  }

  @override
  Widget build(BuildContext context) {
    final panel = BoardPanelInstance(
      id: 'playlist-test',
      type: 'board.playlist',
      title: 'Playlist',
      bounds: const BoardPanelBounds(x: 0, y: 0, width: 380, height: 520),
      state: widget.harness.state,
    );
    return const PlaylistPlugin().buildContent(
      context,
      panel,
      BoardPanelRenderContext(
        isSelected: false,
        onFocus: () {},
        onDelete: () {},
        onShowEditor: () {},
        onUpdateState: (next) {
          widget.harness.updates.add(next);
          setState(() => widget.harness.state = next);
        },
      ),
    );
  }
}

/// Pumps a handful of short frames so stream events and dialogs settle.
Future<void> _pumpOut(WidgetTester tester, [int times = 6]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}
