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
