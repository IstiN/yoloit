import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/utils/text_normalize.dart' as text_normalize;

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

    String? text;

    // Try super_clipboard first.
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard != null) {
        final reader = await clipboard.read();

        // Prefer image formats — use getFile() API for FileFormat types.
        final imageResult = await _tryReadImage(reader);
        if (imageResult != null) return imageResult;

        if (reader.canProvide(Formats.plainText)) {
          text = await reader.readValue(Formats.plainText);
        }
      }
    } catch (_) {
      // ignore super_clipboard failures
    }

    // Fallback to Flutter's standard clipboard API for text.
    if (text == null || text.isEmpty) {
      try {
        final data = await Clipboard.getData('text/plain');
        text = data?.text;
      } catch (_) {
        // ignore fallback failures
      }
    }

    if (text != null && text.isNotEmpty) {
      return _saveText(text);
    }

    return null;
  }

  /// Test seam: super_clipboard has no mockable platform channel in unit
  /// tests, so tests drive the image branch through this wrapper.
  @visibleForTesting
  Future<String?> tryReadImageForTesting(ClipboardReader reader) =>
      _tryReadImage(reader);

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

  String normalizeText(String text) => text_normalize.normalizeText(text);

  Future<String> _saveText(String text) async {
    final ext = _guessExtension(text);
    final file = await _tempFile(ext);
    await file.writeAsString(normalizeText(text));
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

  /// If [text] is a single-line URL, path to an existing file, or path to an
  /// existing directory, returns it as-is. Otherwise returns null so the caller
  /// can fall back to saving a temp file.
  Future<String?> tryResolveTextAsFilePath(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.contains('\n') || trimmed.contains('\r')) return null;

    // URLs should be pasted inline, not wrapped into a .txt file.
    final lower = trimmed.toLowerCase();
    const urlSchemes = ['http://', 'https://', 'ftp://', 'file://'];
    for (final scheme in urlSchemes) {
      if (lower.startsWith(scheme)) return trimmed;
    }

    try {
      final file = File(trimmed);
      if (await file.exists()) {
        return trimmed;
      }
      final dir = Directory(trimmed);
      if (await dir.exists()) {
        return trimmed;
      }
    } catch (_) {
      // ignore path parsing or permission errors
    }
    return null;
  }

  /// Saves the provided [text] to a temp file and returns the absolute path.
  Future<String> saveTextToFile(String text) async {
    final file = await _tempFile('txt');
    await file.writeAsString(normalizeText(text));
    return file.path;
  }

  /// Returns true when [text] is short, single-line and contains no control
  /// characters other than tab, making it safe to paste inline into text
  /// fields instead of wrapping it in a temp file.
  bool isSafeInlineText(String text, {int maxLength = 1000}) {
    if (text.isEmpty || text.length > maxLength) return false;
    if (text.contains('\n') || text.contains('\r')) return false;
    for (final codeUnit in text.codeUnits) {
      if (codeUnit < 32 && codeUnit != 9) return false;
    }
    return true;
  }
}
