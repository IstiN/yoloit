import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/core/platform/platform_dirs.dart';

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
    return _capture(pixelRatio: pixelRatio, format: ui.ImageByteFormat.png);
  }

  /// Capture the current board viewport as a compressed JPEG file.
  ///
  /// Saves to a temp file and returns the path.
  /// Uses low pixel ratio (0.5) for small file size.
  /// Returns null if capture fails.
  Future<String?> captureJpegFile({double pixelRatio = 0.5}) async {
    final bytes = await _capture(
      pixelRatio: pixelRatio,
      format: ui.ImageByteFormat.png,
    );
    if (bytes == null) return null;

    try {
      // Convert PNG bytes to JPEG via dart:ui codec
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final image = frame.image;
      final jpegData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose();
      codec.dispose();

      if (jpegData == null) return null;

      // Save PNG (already compressed enough at low pixelRatio) as the file
      // dart:ui doesn't have native JPEG encoding, so we use PNG at low res
      final tempDir = PlatformDirs.instance.tempDir;
      final dir = Directory(p.join(tempDir, 'board_snapshots'));
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final filePath = p.join(
        dir.path,
        'board_snapshot_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      assert(() { debugPrint('[BoardScreenshot] JPEG save failed: $e'); return true; }());
      return null;
    }
  }

  /// Returns the board snapshot as base64-encoded PNG string.
  Future<String?> captureBase64({double pixelRatio = 0.5}) async {
    final bytes = await _capture(pixelRatio: pixelRatio, format: ui.ImageByteFormat.png);
    if (bytes == null) return null;
    return base64Encode(bytes);
  }

  /// Wait for a single frame to be drawn using a post-frame callback.
  /// Uses [PlatformDispatcher.scheduleFrame] directly to bypass the
  /// [framesEnabled] check — when the app window is not focused (e.g.,
  /// screenshot requested from CLI), [SchedulerBinding.scheduleFrame]
  /// returns early and no frame is ever drawn.
  Future<void> _waitForNextFrame() async {
    final completer = Completer<void>();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!completer.isCompleted) completer.complete();
    });
    // Bypass framesEnabled check — force the engine to pump a frame.
    ui.PlatformDispatcher.instance.scheduleFrame();
    await completer.future.timeout(
      const Duration(milliseconds: 200),
      onTimeout: () {
        assert(() { debugPrint('[BoardScreenshot] frame timeout, proceeding'); return true; }());
      },
    );
  }

  Future<Uint8List?> _capture({
    required double pixelRatio,
    required ui.ImageByteFormat format,
  }) async {
    final key = _boundaryKey;
    if (key == null) {
      assert(() { debugPrint('[BoardScreenshot] no boundary key'); return true; }());
      return null;
    }

    for (var i = 0; i < 5; i++) {
      await _waitForNextFrame();
      final boundary = key.currentContext?.findRenderObject();
      if (boundary is! RenderRepaintBoundary) {
        assert(() { debugPrint('[BoardScreenshot] boundary not ready: ${boundary.runtimeType}'); return true; }());
        continue;
      }

      try {
        final image = await boundary.toImage(pixelRatio: pixelRatio);
        final byteData = await image.toByteData(format: format);
        image.dispose();
        if (byteData != null) return byteData.buffer.asUint8List();
      } catch (e, st) {
        assert(() { debugPrint('[BoardScreenshot] capture failed: $e'); return true; }());
        debugPrintStack(stackTrace: st);
      }
    }
    return null;
  }

  /// Clean up old snapshot files (older than 1 hour).
  Future<void> cleanupOldSnapshots() async {
    try {
      final dir = Directory(
        p.join(PlatformDirs.instance.tempDir, 'board_snapshots'),
      );
      if (!dir.existsSync()) return;
      final cutoff = DateTime.now().subtract(const Duration(hours: 1));
      for (final f in dir.listSync()) {
        if (f is File && f.lastModifiedSync().isBefore(cutoff)) {
          f.deleteSync();
        }
      }
    } catch (_) {}
  }
}
