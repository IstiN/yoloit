import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
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

    // Read plain text through Flutter's built-in clipboard FIRST: it avoids
    // any third-party native clipboard code entirely.
    final text = await _readFlutterText();
    if (text == null || text.isEmpty) {
      // No plain text — the clipboard may hold an image.
      final imageResult = await _tryReadImage();
      if (imageResult != null) return imageResult;
    }

    if (text != null && text.isNotEmpty) {
      return _saveText(text);
    }

    return null;
  }

  Future<String?> _readFlutterText() async {
    try {
      final data = await Clipboard.getData('text/plain');
      return data?.text;
    } catch (_) {
      return null;
    }
  }

  /// Reads the image from the system pasteboard and saves it to a temp file.
  /// Returns null when there is no image or reading fails.
  Future<String?> _tryReadImage() async {
    Uint8List? bytes;
    try {
      bytes = await Pasteboard.image;
    } catch (_) {
      // pasteboard uses a plain MethodChannel: failures arrive here as
      // catchable PlatformExceptions (unlike the old Rust-based
      // super_clipboard, which aborted the whole process on panic).
      return null;
    }
    if (bytes == null || bytes.isEmpty) return null;
    return _saveBytes(bytes, _sniffImageExtension(bytes));
  }

  /// Picks a file extension from magic bytes. macOS always hands us PNG
  /// (the plugin converts NSImage via TIFF), but other platforms may put
  /// the original encoding on the pasteboard.
  String _sniffImageExtension(Uint8List bytes) {
    if (bytes.length >= 4 && bytes[0] == 0x89 && bytes[1] == 0x50) {
      return 'png'; // 0x89 'P'
    }
    if (bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8) {
      return 'jpg';
    }
    if (bytes.length >= 4 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif'; // 'GIF8'
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46) {
      return 'webp'; // 'RIFF'....'WEBP'
    }
    return 'png';
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
