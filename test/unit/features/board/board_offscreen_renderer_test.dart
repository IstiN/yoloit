import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_offscreen_renderer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  BoardDocument _boardWithPanels(List<BoardPanelInstance> panels) {
    return BoardDocument(
      id: 'test-board',
      name: 'Test Board',
      panels: panels,
    );
  }

  BoardPanelInstance _panel(
    String type, {
    Map<String, dynamic> state = const {},
    double width = 320,
    double height = 500,
  }) {
    return BoardPanelInstance(
      id: 'panel-$type',
      type: type,
      title: 'Test',
      bounds: BoardPanelBounds(x: 40, y: 40, width: width, height: height),
      state: state,
    );
  }

  test('renderBoard returns PNG for file tree panel without ancestor errors', () async {
    final board = _boardWithPanels([
      _panel(
        'board.filetree',
        state: {
          'rootPath': Directory.current.path,
          'expandedDirs': <String>[],
          'selectedFile': '',
        },
      ),
    ]);

    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previousHandler?.call(details);
    };

    try {
      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(480, 320),
        pixelRatio: 1.0,
      );

      expect(png, isNotNull);
      expect(png!.length, greaterThan(100));
      expect(
        errors.where(
          (details) {
            final message = details.exceptionAsString();
            return message.contains('No Overlay widget found') ||
                message.contains('No Material widget found') ||
                message.contains('No MediaQuery widget ancestor found');
          },
        ),
        isEmpty,
      );
    } finally {
      FlutterError.onError = previousHandler;
    }
  });

  test('renderBoard returns PNG for checklist panel with localizations', () async {
    final board = _boardWithPanels([
      _panel(
        'board.checklist',
        state: {
          'items': [
            {'text': 'Buy milk', 'done': false},
            {'text': 'Walk dog', 'done': true},
          ],
        },
        width: 280,
        height: 240,
      ),
    ]);

    final errors = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previousHandler?.call(details);
    };

    try {
      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(480, 320),
        pixelRatio: 1.0,
      );

      expect(png, isNotNull);
      expect(
        errors.where(
          (details) =>
              details.exceptionAsString().contains('No MaterialLocalizations'),
        ),
        isEmpty,
      );
    } finally {
      FlutterError.onError = previousHandler;
    }
  });

  test('renderBoard uses placeholders for native-only plugins', () async {
    final board = _boardWithPanels([
      _panel('board.playlist'),
      _panel('board.webpage'),
      _panel('board.terminal'),
    ]);

    final png = await BoardOffscreenRenderer.instance.renderBoard(
      board,
      size: const Size(480, 320),
      pixelRatio: 1.0,
    );

    expect(png, isNotNull);
    expect(png!.length, greaterThan(100));
  });

  test('renderPanel paints SVG file previews in offscreen snapshots', () async {
    final tmp = await Directory.systemTemp.createTemp('yoloit-svg-preview-');
    addTearDown(() async {
      if (await tmp.exists()) {
        await tmp.delete(recursive: true);
      }
    });
    final svgFile = File('${tmp.path}/preview.svg');
    await svgFile.writeAsString('''
<svg xmlns="http://www.w3.org/2000/svg" width="220" height="160" viewBox="0 0 220 160">
  <rect width="220" height="160" fill="#f21616"/>
  <circle cx="110" cy="80" r="44" fill="#ffffff"/>
</svg>
''');

    final panel = _panel(
      'board.file.preview',
      state: {'path': svgFile.path, 'title': 'preview.svg'},
      width: 320,
      height: 260,
    );
    final board = _boardWithPanels([panel]);

    final png = await BoardOffscreenRenderer.instance.renderPanel(
      board,
      panel,
      pixelRatio: 1.0,
    );

    expect(png, isNotNull);
    final redPixels = await _countRedPixels(png!);
    expect(redPixels, greaterThan(250));

    final boardPng = await BoardOffscreenRenderer.instance.renderBoard(
      board,
      size: const Size(480, 320),
      pixelRatio: 1.0,
    );

    expect(boardPng, isNotNull);
    final boardRedPixels = await _countRedPixels(boardPng!);
    expect(boardRedPixels, greaterThan(250));
  });
  group('capCaptureSize', () {
    test('keeps small requests unchanged (below the cap)', () {
      final capped = BoardOffscreenRenderer.capCaptureSize(
        const Size(480, 320),
        1.5,
      );
      expect(capped.size, const Size(480, 320));
      expect(capped.pixelRatio, 1.5);
    });

    test('keeps requests exactly at the cap unchanged', () {
      // 400x400 @ 1.0 = 160000 px; 200x200 @ 2.0 = 160000 px — both under.
      // 4096x4096 is exactly 2^24 px.
      final capped = BoardOffscreenRenderer.capCaptureSize(
        const Size(4096, 4096),
        1.0,
      );
      expect(capped.size, const Size(4096, 4096));
      expect(capped.pixelRatio, 1.0);
    });

    test('reduces pixelRatio for oversized requests (4000x4000 @ 2.0)', () {
      final capped = BoardOffscreenRenderer.capCaptureSize(
        const Size(4000, 4000),
        2.0,
      );
      final px = capped.size.width * capped.pixelRatio;
      final py = capped.size.height * capped.pixelRatio;
      expect(px * py, lessThanOrEqualTo(
        BoardOffscreenRenderer.maxCapturePhysicalPixels.toDouble(),
      ));
      // Preferred strategy: logical size untouched, ratio reduced.
      expect(capped.size, const Size(4000, 4000));
      expect(capped.pixelRatio, lessThan(2.0));
      expect(capped.pixelRatio, greaterThanOrEqualTo(1.0));
    });

    test('clamps logical dimensions when ratio alone cannot hit the cap', () {
      final capped = BoardOffscreenRenderer.capCaptureSize(
        const Size(5000, 5000),
        1.0,
      );
      expect(capped.pixelRatio, 1.0);
      expect(capped.size.width, lessThan(5000));
      expect(capped.size.height, lessThan(5000));
      final px = capped.size.width * capped.pixelRatio;
      final py = capped.size.height * capped.pixelRatio;
      expect(px * py, lessThanOrEqualTo(
        BoardOffscreenRenderer.maxCapturePhysicalPixels.toDouble(),
      ));
    });
  });

  group('capture disposal', () {
    final originalCapturer = BoardOffscreenRenderer.imageCapturer;
    final originalEncoder = BoardOffscreenRenderer.imageEncoder;

    setUp(() {
      BoardOffscreenRenderer.imageCapturer = originalCapturer;
      BoardOffscreenRenderer.imageEncoder = originalEncoder;
    });

    tearDown(() {
      BoardOffscreenRenderer.imageCapturer = originalCapturer;
      BoardOffscreenRenderer.imageEncoder = originalEncoder;
    });

    test('disposes the captured image on the success path', () async {
      final board = _boardWithPanels([_panel('board.playlist')]);
      final captured = await createTestImage(width: 8, height: 8);
      BoardOffscreenRenderer.imageCapturer =
          (boundary, {required pixelRatio}) async => captured;

      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(320, 240),
        pixelRatio: 1.0,
      );

      expect(png, isNotNull);
      expect(captured.debugDisposed, isTrue);
    });

    test('disposes the captured image when encoding throws', () async {
      final board = _boardWithPanels([_panel('board.playlist')]);
      final captured = await createTestImage(width: 8, height: 8);
      BoardOffscreenRenderer.imageCapturer =
          (boundary, {required pixelRatio}) async => captured;
      BoardOffscreenRenderer.imageEncoder = (image, format) async {
        throw StateError('encode boom');
      };

      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(320, 240),
        pixelRatio: 1.0,
      );

      // Error is swallowed by _withErrorBuilder (returns null), but the
      // native image must still be disposed.
      expect(png, isNull);
      expect(captured.debugDisposed, isTrue);
    });

    test('cancel path returns null without throwing', () async {
      final board = _boardWithPanels([_panel('board.playlist')]);
      final token = CancelToken()..cancel();

      final png = await BoardOffscreenRenderer.instance.renderBoard(
        board,
        size: const Size(320, 240),
        pixelRatio: 1.0,
        cancelToken: token,
      );

      expect(png, isNull);
    });
  });

  test('renderPanel caps physical pixels of oversized panels', () async {
    // 4000x4000 logical @ 2.0 would be a single 8000x8000 (~244 MiB) image.
    final panel = _panel('board.playlist', width: 4000, height: 4000);
    final board = _boardWithPanels([panel]);

    final png = await BoardOffscreenRenderer.instance.renderPanel(
      board,
      panel,
      pixelRatio: 2.0,
    );

    expect(png, isNotNull);
    final codec = await ui.instantiateImageCodec(png!);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    expect(
      image.width * image.height,
      lessThanOrEqualTo(BoardOffscreenRenderer.maxCapturePhysicalPixels),
    );
    // Capping reduced the ratio (was requested at 2.0 -> 8000x8000 physical).
    expect(image.width, lessThan(8000));
    image.dispose();
    codec.dispose();
  });

  group('capture polling', () {
    final originalSleeper = BoardOffscreenRenderer.pollSleeper;
    final originalElapsedOverride = BoardOffscreenRenderer.pollElapsedMsOverride;

    setUp(() {
      BoardOffscreenRenderer.pollSleeper = originalSleeper;
      BoardOffscreenRenderer.pollElapsedMsOverride = originalElapsedOverride;
      HeadlessRenderRegistry.activeTasks.clear();
    });

    tearDown(() {
      BoardOffscreenRenderer.pollSleeper = originalSleeper;
      BoardOffscreenRenderer.pollElapsedMsOverride = originalElapsedOverride;
      HeadlessRenderRegistry.activeTasks.clear();
    });

    /// Installs a fake clock: the sleeper advances the clock by the slept
    /// interval, so 15s-timeout scenarios run instantly while the loop sees
    /// a realistic elapsed time.
    void installFakeClock(List<Duration> intervals) {
      var elapsed = 0;
      BoardOffscreenRenderer.pollElapsedMsOverride = () => elapsed;
      BoardOffscreenRenderer.pollSleeper = (duration) async {
        intervals.add(duration);
        elapsed += duration.inMilliseconds;
      };
    }

    int totalMs(List<Duration> intervals) =>
        intervals.fold<int>(0, (sum, d) => sum + d.inMilliseconds);

    test(
      'a task stuck from earlier work does not extend the capture',
      () async {
        HeadlessRenderRegistry.activeTasks.add('stuck:earlier');
        final intervals = <Duration>[];
        installFakeClock(intervals);

        final png = await BoardOffscreenRenderer.instance.renderBoard(
          _boardWithPanels([_panel('board.playlist')]),
          size: const Size(320, 240),
          pixelRatio: 1.0,
        );

        expect(png, isNotNull);
        // The 15s timeout is not hit: the preexisting task is subtracted via
        // the start snapshot. Only the 4-turn quiet debounce elapses; its
        // sleeps back off as the (static, task-free) set stays unchanged.
        expect(totalMs(intervals), 400);
        expect(intervals, [
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 100),
          const Duration(milliseconds: 200),
        ]);
      },
    );

    test(
      'a task registered during the capture still gates completion',
      () async {
        final intervals = <Duration>[];
        var elapsed = 0;
        var registered = false;
        BoardOffscreenRenderer.pollElapsedMsOverride = () => elapsed;
        BoardOffscreenRenderer.pollSleeper = (duration) async {
          intervals.add(duration);
          elapsed += duration.inMilliseconds;
          if (!registered) {
            // First poll: the snapshot is already taken, so this task belongs
            // to THIS capture and must gate completion.
            registered = true;
            HeadlessRenderRegistry.activeTasks.add('during:js-engine');
          } else if (elapsed >= 600) {
            HeadlessRenderRegistry.activeTasks.remove('during:js-engine');
          }
        };

        final png = await BoardOffscreenRenderer.instance.renderBoard(
          _boardWithPanels([_panel('board.playlist')]),
          size: const Size(320, 240),
          pixelRatio: 1.0,
        );

        expect(png, isNotNull);
        // The capture kept polling until the task finished at 600ms, then
        // debounced 4 quiet turns — well under the 15s timeout.
        expect(totalMs(intervals), greaterThan(600));
        expect(totalMs(intervals), lessThan(15000));
      },
    );

    test('sequential task chains are still awaited', () async {
      var elapsed = 0;
      var phase = 0;
      BoardOffscreenRenderer.pollElapsedMsOverride = () => elapsed;
      BoardOffscreenRenderer.pollSleeper = (duration) async {
        elapsed += duration.inMilliseconds;
        if (phase == 0) {
          phase = 1;
          HeadlessRenderRegistry.activeTasks.add('during:A');
        } else if (phase == 1 && elapsed >= 500) {
          // Task A finishes and registers task B before completing.
          phase = 2;
          HeadlessRenderRegistry.activeTasks
            ..remove('during:A')
            ..add('during:B');
        } else if (phase == 2 && elapsed >= 120) {
          phase = 3;
          HeadlessRenderRegistry.activeTasks.remove('during:B');
        }
      };

      final png = await BoardOffscreenRenderer.instance.renderBoard(
        _boardWithPanels([_panel('board.playlist')]),
        size: const Size(320, 240),
        pixelRatio: 1.0,
      );

      expect(png, isNotNull);
      // Completion waited for task B (gated beyond its 120ms lifetime).
      expect(elapsed, greaterThan(120));
      expect(elapsed, lessThan(15000));
      expect(HeadlessRenderRegistry.activeTasks, isEmpty);
    });

    test(
      'poll interval backs off while the task set is static and resets on '
      'change',
      () async {
        final intervals = <Duration>[];
        var polls = 0;
        var elapsed = 0;
        BoardOffscreenRenderer.pollElapsedMsOverride = () => elapsed;
        BoardOffscreenRenderer.pollSleeper = (duration) async {
          intervals.add(duration);
          elapsed += duration.inMilliseconds;
          polls++;
          if (polls == 1) {
            HeadlessRenderRegistry.activeTasks.add('during:task');
          } else if (polls == 2) {
            HeadlessRenderRegistry.activeTasks.remove('during:task');
          }
        };

        await BoardOffscreenRenderer.instance.renderBoard(
          _boardWithPanels([_panel('board.playlist')]),
          size: const Size(320, 240),
          pixelRatio: 1.0,
        );

        // 50ms until the first change is observed, reset to 50ms by the
        // register/remove changes, then 50 -> 100 -> 200 growth over the
        // final quiet turns.
        expect(intervals, [
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 50),
          const Duration(milliseconds: 100),
          const Duration(milliseconds: 200),
        ]);
      },
    );

    test(
      '15s timeout still fires for a permanently stuck task from this '
      'capture',
      () async {
        final intervals = <Duration>[];
        var elapsed = 0;
        BoardOffscreenRenderer.pollElapsedMsOverride = () => elapsed;
        BoardOffscreenRenderer.pollSleeper = (duration) async {
          intervals.add(duration);
          elapsed += duration.inMilliseconds;
          // Re-add on every poll: the task never completes.
          HeadlessRenderRegistry.activeTasks.add('during:stuck');
        };

        final png = await BoardOffscreenRenderer.instance.renderBoard(
          _boardWithPanels([_panel('board.playlist')]),
          size: const Size(320, 240),
          pixelRatio: 1.0,
        );

        // The timeout does not fail the capture; it proceeds to paint.
        expect(png, isNotNull);
        expect(elapsed, greaterThanOrEqualTo(15000));
        expect(elapsed, lessThan(16000));
        // Backoff caps the interval at 400ms: ~40 polls instead of the
        // previous fixed-50ms ~300 polls for the same 15s window.
        expect(intervals.last, CapturePollTracker.intervalCap);
        expect(intervals.length, lessThan(60));
      },
    );

    group('CapturePollTracker', () {
      test('nextPollInterval doubles up to the cap and resets on change', () {
        var interval = CapturePollTracker.intervalStart;
        interval = nextPollInterval(interval, taskSetChanged: false);
        expect(interval, const Duration(milliseconds: 100));
        interval = nextPollInterval(interval, taskSetChanged: false);
        expect(interval, const Duration(milliseconds: 200));
        interval = nextPollInterval(interval, taskSetChanged: false);
        expect(interval, const Duration(milliseconds: 400));
        expect(
          nextPollInterval(interval, taskSetChanged: false),
          CapturePollTracker.intervalCap,
        );
        expect(
          nextPollInterval(interval, taskSetChanged: true),
          CapturePollTracker.intervalStart,
        );
      });

      test('subtracts the start snapshot from the quiet condition', () {
        final tracker = CapturePollTracker({'stuck:old'});
        expect(tracker.recordObservation({'stuck:old'}), isFalse);
        expect(tracker.recordObservation({'stuck:old'}), isFalse);
        expect(tracker.recordObservation({'stuck:old'}), isFalse);
        expect(tracker.recordObservation({'stuck:old'}), isTrue);

        final gating = CapturePollTracker({'stuck:old'});
        expect(
          gating.recordObservation({'stuck:old', 'during:new'}),
          isFalse,
        );
        // A task appearing mid-capture keeps the window from advancing...
        expect(gating.quietTurns, 0);
        // ...and the window refills only after it disappears.
        expect(gating.recordObservation({'stuck:old'}), isFalse);
        expect(gating.recordObservation({'stuck:old'}), isFalse);
        expect(gating.recordObservation({'stuck:old'}), isFalse);
        expect(gating.recordObservation({'stuck:old'}), isTrue);
      });

      test('backs off while the task set is static and resets on change', () {
        final tracker = CapturePollTracker({});
        tracker.recordObservation({'a'});
        expect(tracker.interval, CapturePollTracker.intervalStart);
        tracker.recordObservation({'a'});
        expect(tracker.interval, const Duration(milliseconds: 100));
        tracker.recordObservation({'a', 'b'});
        expect(tracker.interval, CapturePollTracker.intervalStart);
        tracker.recordObservation({'a', 'b'});
        expect(tracker.interval, const Duration(milliseconds: 100));
      });
    });
  });
}

Future<int> _countRedPixels(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  try {
    final frame = await codec.getNextFrame();
    final image = frame.image;
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return 0;
      final bytes = data.buffer.asUint8List();
      var count = 0;
      for (var i = 0; i < bytes.length; i += 4) {
        final r = bytes[i];
        final g = bytes[i + 1];
        final b = bytes[i + 2];
        final a = bytes[i + 3];
        if (a > 180 && r > 190 && g < 80 && b < 80) {
          count++;
        }
      }
      return count;
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
