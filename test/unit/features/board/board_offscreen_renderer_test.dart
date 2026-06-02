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
