import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Singleton service for capturing board screenshots.
///
/// The [BoardView] registers its [RepaintBoundary] key here so the CLI
/// server can request a PNG capture without holding a direct widget ref.
class BoardScreenshotService {
  BoardScreenshotService._();
  static final BoardScreenshotService instance = BoardScreenshotService._();

  GlobalKey? _boundaryKey;

  /// Called by [BoardView] to register the repaint boundary key.
  void registerBoundaryKey(GlobalKey key) => _boundaryKey = key;

  /// Capture the current board viewport as PNG bytes.
  ///
  /// [pixelRatio] controls resolution (1.0 = screen pixels, 2.0 = 2× retina).
  /// Returns null if no boundary is registered or capture fails.
  Future<Uint8List?> capturePng({double pixelRatio = 1.0}) async {
    final key = _boundaryKey;
    if (key == null) return null;

    final boundary = key.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;

    try {
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return byteData?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }
}
