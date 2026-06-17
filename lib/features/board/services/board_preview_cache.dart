import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:yoloit/features/board/model/board_models.dart';

/// Disk cache for board overview thumbnails with revision-based invalidation.
///
/// A cached preview is considered fresh when its sidecar fingerprint matches the
/// board's current [historyRevision], viewport, and theme key.
class BoardPreviewCache {
  BoardPreviewCache({Directory? rootDir})
    : _rootDir =
          rootDir ??
          Directory('${Directory.systemTemp.path}/yoloit_board_previews');

  static final BoardPreviewCache instance = BoardPreviewCache();

  final Directory _rootDir;

  static int historyRevisionOf(BoardDocument board) {
    return (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
  }

  /// Stable fingerprint for whether a cached PNG still matches board content.
  static String fingerprint(BoardDocument board, {String themeKey = ''}) {
    final viewport = board.viewport;
    return '${historyRevisionOf(board)}:'
        '${viewport.scale.toStringAsFixed(4)}:'
        '${viewport.translation.dx.toStringAsFixed(2)}:'
        '${viewport.translation.dy.toStringAsFixed(2)}:'
        '$themeKey';
  }

  File pngFile(String boardId) => File('${_rootDir.path}/$boardId.png');

  File metaFile(String boardId) => File('${_rootDir.path}/$boardId.meta.json');

  bool isFresh(BoardDocument board, {String themeKey = ''}) {
    if (!pngFile(board.id).existsSync()) return false;
    final meta = _readMeta(board.id);
    if (meta == null) return false;
    return meta['fingerprint'] == fingerprint(board, themeKey: themeKey);
  }

  Uint8List? loadPng(BoardDocument board, {String themeKey = ''}) {
    if (!isFresh(board, themeKey: themeKey)) return null;
    try {
      return pngFile(board.id).readAsBytesSync();
    } catch (_) {
      return null;
    }
  }

  void save(BoardDocument board, Uint8List bytes, {String themeKey = ''}) {
    try {
      if (!_rootDir.existsSync()) {
        _rootDir.createSync(recursive: true);
      }
      pngFile(board.id).writeAsBytesSync(bytes);
      metaFile(board.id).writeAsStringSync(
        jsonEncode({
          'fingerprint': fingerprint(board, themeKey: themeKey),
        }),
      );
    } catch (_) {
      // Best-effort — overview previews must not crash the app.
    }
  }

  Map<String, dynamic>? _readMeta(String boardId) {
    final file = metaFile(boardId);
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }
}
