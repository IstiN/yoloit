import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';

/// Saves the current clipboard content to a temp file under /tmp/yoloit_clip/
/// and returns the absolute path, or null if the clipboard is empty.
class ClipboardFileService {
  ClipboardFileService._();
  static final ClipboardFileService instance = ClipboardFileService._();

  static String get _dir => '${PlatformDirs.instance.tempDir}/yoloit_clip';
  bool _hasCleanedUp = false;

  Future<String?> saveClipboardToFile() async {
    if (!_hasCleanedUp) {
      _hasCleanedUp = true;
      unawaited(_cleanupOldFiles());
    }
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return null;

    final reader = await clipboard.read();

    // Prefer image formats — use getFile() API for FileFormat types.
    final imageResult = await _tryReadImage(reader);
    if (imageResult != null) return imageResult;

    // Fall back to plain text.
    if (reader.canProvide(Formats.plainText)) {
      final text = await reader.readValue(Formats.plainText);
      if (text == null || text.isEmpty) return null;
      return _saveText(text);
    }

    return null;
  }

  Future<String?> _tryReadImage(ClipboardReader reader) async {
    final formats = [
      (Formats.png, 'png'),
      (Formats.jpeg, 'jpg'),
      (Formats.gif, 'gif'),
      (Formats.webp, 'webp'),
    ];

    for (final (format, ext) in formats) {
      if (!reader.canProvide(format)) continue;

      Uint8List? bytes;
      final completer = Completer<Uint8List?>();

      reader.getFile(format, (file) async {
        try {
          completer.complete(await file.readAll());
        } catch (_) {
          completer.complete(null);
        }
      });

      bytes = await completer.future;
      if (bytes != null && bytes.isNotEmpty) return _saveBytes(bytes, ext);
    }
    return null;
  }

  Future<String> _saveBytes(Uint8List bytes, String ext) async {
    final file = await _tempFile(ext);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<String> _saveText(String text) async {
    final ext = _guessExtension(text);
    final file = await _tempFile(ext);
    await file.writeAsString(text);
    return file.path;
  }

  Future<File> _tempFile(String ext) async {
    await Directory(_dir).create(recursive: true);
    final ts = DateTime.now().millisecondsSinceEpoch;
    return File('$_dir/clip_$ts.$ext');
  }

  /// Deletes clip files older than 24 hours.
  Future<void> _cleanupOldFiles() async {
    final dir = Directory(_dir);
    if (!await dir.exists()) return;
    final now = DateTime.now();
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified).inHours > 24) {
          await entity.delete();
        }
      } catch (_) {
        // ignore cleanup failures
      }
    }
  }

  /// Clipboard text is always saved as .txt to avoid heuristic mis-detection.
  String _guessExtension(String text) {
    return 'txt';
  }
}
