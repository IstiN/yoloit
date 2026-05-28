import 'dart:io';

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
}
