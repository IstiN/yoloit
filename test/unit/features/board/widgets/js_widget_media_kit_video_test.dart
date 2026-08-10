import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:yoloit/features/board/widgets/js_widget_media_kit_video.dart';

/// In-memory [Player] replacement: the real media_kit player needs native
/// libmpv, which is unavailable in unit tests. Unimplemented members throw
/// via [noSuchMethod], so unexpected usage fails loudly.
class _FakePlayer implements Player {
  PlayerState _state = const PlayerState();

  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final videoParamsCtl = StreamController<VideoParams>.broadcast();

  final List<String> opened = [];
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
  Future<void> dispose() async {
    disposed = true;
    await positionCtl.close();
    await durationCtl.close();
    await playingCtl.close();
    await videoParamsCtl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Stream<VideoParams> get videoParams => _player.videoParamsCtl.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeVideoController implements VideoController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// [_FakePlayer] variant whose [open] method blocks on a [Completer] so tests
/// can control when the async-initialization future resolves.
class _BlockingFakePlayer implements Player {
  _BlockingFakePlayer();

  PlayerState _state = const PlayerState();
  final openCompleter = Completer<void>();

  final positionCtl = StreamController<Duration>.broadcast();
  final durationCtl = StreamController<Duration>.broadcast();
  final playingCtl = StreamController<bool>.broadcast();
  final videoParamsCtl = StreamController<VideoParams>.broadcast();

  @override
  PlayerState get state => _state;
  set state(PlayerState value) => _state = value;

  @override
  PlayerStream get stream => _BlockingPlayerStream(this);

  @override
  Future<void> open(Playable playable, {bool play = true}) => openCompleter.future;

  @override
  Future<void> dispose() async {
    await positionCtl.close();
    await durationCtl.close();
    await playingCtl.close();
    await videoParamsCtl.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _BlockingPlayerStream implements PlayerStream {
  const _BlockingPlayerStream(this._player);

  final _BlockingFakePlayer _player;

  @override
  Stream<Duration> get position => _player.positionCtl.stream;

  @override
  Stream<Duration> get duration => _player.durationCtl.stream;

  @override
  Stream<bool> get playing => _player.playingCtl.stream;

  @override
  Stream<VideoParams> get videoParams => _player.videoParamsCtl.stream;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakePlayer player;

  setUp(() {
    player = _FakePlayer();
    MediaKitVideoController.debugPlayerFactory = () => player;
    MediaKitVideoController.debugVideoControllerFactory =
        (_) => _FakeVideoController();
  });

  tearDown(() {
    MediaKitVideoController.debugPlayerFactory = null;
    MediaKitVideoController.debugVideoControllerFactory = null;
  });

  Future<void> flushMicrotasks() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  group('MediaKitVideoController.create', () {
    test('opens the media source and forwards player streams', () async {
      final controller = await MediaKitVideoController.create(
        'file:///tmp/clip.mp4',
      );
      addTearDown(controller.dispose);

      // Media normalizes file:// URIs to plain local paths.
      expect(player.opened, ['/tmp/clip.mp4']);

      final positions = <Duration>[];
      final durations = <Duration>[];
      final playingStates = <bool>[];
      final subs = [
        controller.positionStream.listen(positions.add),
        controller.durationStream.listen(durations.add),
        controller.playingStream.listen(playingStates.add),
      ];
      addTearDown(() async {
        for (final sub in subs) {
          await sub.cancel();
        }
      });

      player.positionCtl.add(const Duration(seconds: 2));
      player.durationCtl.add(const Duration(minutes: 1));
      player.playingCtl.add(true);
      await flushMicrotasks();

      expect(positions, [const Duration(seconds: 2)]);
      expect(durations, [const Duration(minutes: 1)]);
      expect(playingStates, [true]);
    });

    test('pushes aspect ratio updates when video params arrive', () async {
      final controller = await MediaKitVideoController.create('clip.mp4');
      addTearDown(controller.dispose);

      final ratios = <double?>[];
      final sub = controller.aspectRatioStream.listen(ratios.add);
      addTearDown(sub.cancel);

      player.videoParamsCtl.add(const VideoParams(w: 1920, h: 1080));
      // Missing dimensions must not emit.
      player.videoParamsCtl.add(const VideoParams());
      // Zero height must not emit (division guard).
      player.videoParamsCtl.add(const VideoParams(w: 10, h: 0));
      await flushMicrotasks();

      expect(ratios, [1920 / 1080]);
    });
  });

  group('MediaKitVideoController.aspectRatio', () {
    test('returns null before any video params are known', () async {
      final controller = await MediaKitVideoController.create('clip.mp4');
      addTearDown(controller.dispose);

      expect(controller.aspectRatio, isNull);
    });

    test('computes w/h from the current player state', () async {
      final controller = await MediaKitVideoController.create('clip.mp4');
      addTearDown(controller.dispose);

      player.state = const PlayerState(
        videoParams: VideoParams(w: 4, h: 2),
      );
      expect(controller.aspectRatio, 2.0);
    });

    test('returns null when height is zero or width missing', () async {
      final controller = await MediaKitVideoController.create('clip.mp4');
      addTearDown(controller.dispose);

      player.state = const PlayerState(videoParams: VideoParams(w: 4, h: 0));
      expect(controller.aspectRatio, isNull);

      player.state = const PlayerState(videoParams: VideoParams(h: 2));
      expect(controller.aspectRatio, isNull);
    });
  });

  group('MediaKitVideoController.buildVideo', () {
    testWidgets('honors fit and explicit size', (tester) async {
      late MediaKitVideoController controller;
      await tester.runAsync(() async {
        controller = await MediaKitVideoController.create('clip.mp4');
      });
      addTearDown(controller.dispose);

      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final video = controller.buildVideo(
        context!,
        fit: BoxFit.cover,
        width: 100,
        height: 50,
      );

      expect(video, isA<Video>());
      final videoWidget = video as Video;
      expect(videoWidget.fit, BoxFit.cover);
      expect(videoWidget.width, 100);
      expect(videoWidget.height, 50);
    });

    testWidgets('defaults to BoxFit.contain without explicit size', (
      tester,
    ) async {
      late MediaKitVideoController controller;
      await tester.runAsync(() async {
        controller = await MediaKitVideoController.create('clip.mp4');
      });
      addTearDown(controller.dispose);

      BuildContext? context;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (ctx) {
              context = ctx;
              return const SizedBox();
            },
          ),
        ),
      );

      final video = controller.buildVideo(context!);

      expect(video, isA<Video>());
      final videoWidget = video as Video;
      expect(videoWidget.fit, BoxFit.contain);
      expect(videoWidget.width, isNull);
      expect(videoWidget.height, isNull);
    });
  });

  group('MediaKitVideoController.dispose', () {
    test('disposes the underlying player', () async {
      final controller = await MediaKitVideoController.create('clip.mp4');

      await controller.dispose();

      expect(player.disposed, isTrue);
    });
  });

  group('_AsyncVideoController.buildVideo', () {
    testWidgets('shows a spinner before the future completes', (tester) async {
      // Use a blocking player so we can control when the internal
      // MediaKitVideoController.create future resolves.
      final blockingPlayer = _BlockingFakePlayer();
      MediaKitVideoController.debugPlayerFactory = () => blockingPlayer;
      MediaKitVideoController.debugVideoControllerFactory =
          (_) => _FakeVideoController();

      // Capture a BuildContext from a minimal tree.
      BuildContext? capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      // Create the async controller — player.open hasn't completed yet, so
      // _delegate is still null and buildVideo shows a FutureBuilder spinner.
      final controller = MediaKitVideoController.asyncForTest('clip.mp4');
      addTearDown(controller.dispose);

      final built = controller.buildVideo(capturedContext!);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: built)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Clean up: complete the future before the widget tree is torn down so
      // no pending timers are left behind.
      blockingPlayer.openCompleter.complete();
      await tester.runAsync(() async {
        await flushMicrotasks();
      });
    });

    testWidgets('returns a Video widget after the future completes', (
      tester,
    ) async {
      final blockingPlayer = _BlockingFakePlayer();
      MediaKitVideoController.debugPlayerFactory = () => blockingPlayer;
      MediaKitVideoController.debugVideoControllerFactory =
          (_) => _FakeVideoController();

      BuildContext? capturedContext;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                capturedContext = ctx;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      final controller = MediaKitVideoController.asyncForTest('clip.mp4');
      addTearDown(controller.dispose);

      // Allow the create() future to resolve.
      blockingPlayer.openCompleter.complete();
      await tester.runAsync(() async {
        await flushMicrotasks();
      });

      // After completion _delegate is set, so buildVideo delegates directly
      // and returns a Video widget (not a FutureBuilder).
      final built = controller.buildVideo(capturedContext!);
      expect(built, isA<Video>());
    });
  });
}
