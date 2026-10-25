import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:yoloit/features/board/model/board_models.dart';

/// Disk cache for board overview thumbnails with revision-based invalidation.
///
/// A cached preview is considered fresh when its sidecar fingerprint matches the
/// board's current [historyRevision] and theme key.
class BoardPreviewCache {
  BoardPreviewCache({Directory? rootDir})
    : _rootDir =
          rootDir ??
          Directory('${Directory.systemTemp.path}/yoloit_board_previews');

  static final BoardPreviewCache instance = BoardPreviewCache();

  final Directory _rootDir;

  String get _previewDir => p.join(_rootDir.path, 'board_previews');

  static int historyRevisionOf(BoardDocument board) {
    return (board.metadata['historyRevision'] as num?)?.toInt() ?? 0;
  }

  /// Stable fingerprint for whether a cached PNG still matches board content.
  ///
  /// Overview thumbnails always fit all panels (not viewport), so viewport is
  /// intentionally excluded. Bump [_renderMode] when capture logic changes.
  static const _renderMode = 'fit-all-v3';

  static String fingerprint(BoardDocument board, {String themeKey = ''}) {
    return '$_renderMode:${historyRevisionOf(board)}:$themeKey';
  }

  File pngFile(String boardId) => File(p.join(_previewDir, '$boardId.png'));

  File metaFile(String boardId) => File(p.join(_previewDir, '$boardId.meta.json'));

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
      final previewDir = Directory(_previewDir);
      if (!previewDir.existsSync()) {
        previewDir.createSync(recursive: true);
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

  /// Deletes the cached PNG and sidecar for [boardId], if present.
  ///
  /// Called when a board is deleted so previews do not linger on disk.
  void deleteForBoard(String boardId) {
    try {
      pngFile(boardId).deleteSync();
      metaFile(boardId).deleteSync();
    } catch (_) {
      // Best-effort — overview previews must not crash the app.
    }
  }

  /// Board ids that currently have a cached PNG on disk.
  ///
  /// Returns an empty list when the preview directory cannot be enumerated.
  List<String> cachedBoardIds() {
    final previewDir = Directory(_previewDir);
    if (!previewDir.existsSync()) return const [];
    try {
      return previewDir
          .listSync()
          .whereType<File>()
          .map((file) => p.basename(file.path))
          .where((name) => name.endsWith('.png'))
          .map((name) => name.substring(0, name.length - '.png'.length))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  /// Deletes cached previews whose board id is not in [validBoardIds].
  ///
  /// Defensive: never throws and never deletes anything when the cache
  /// directory cannot be enumerated.
  void sweepOrphans(Set<String> validBoardIds) {
    final cached = cachedBoardIds();
    if (cached.isEmpty) return;
    for (final id in cached) {
      if (!validBoardIds.contains(id)) {
        deleteForBoard(id);
      }
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
