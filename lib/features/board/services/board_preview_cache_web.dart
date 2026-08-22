import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/features/board/model/board_models.dart';

/// Web-safe cache for board overview thumbnails.
///
/// Uses [FileStorageAdapter] for persistence and an in-memory cache so the
/// synchronous [isFresh] / [loadPng] API can still return hits within a session.
class BoardPreviewCache {
  BoardPreviewCache({this._rootDir});

  static final BoardPreviewCache instance = BoardPreviewCache();

  final String? _rootDir;

  final _memoryPng = <String, Uint8List>{};
  final _memoryMeta = <String, String>{};

  String get _scopedPrefix => _rootDir == null ? '' : '$_rootDir/';

  String _pngPath(String boardId) => '${_scopedPrefix}board_previews/$boardId.png';

  String _metaPath(String boardId) =>
      '${_scopedPrefix}board_previews/$boardId.meta.json';

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

  WebCacheFile pngFile(String boardId) => WebCacheFile(_pngPath(boardId));

  WebCacheFile metaFile(String boardId) => WebCacheFile(_metaPath(boardId));

  bool isFresh(BoardDocument board, {String themeKey = ''}) {
    final meta = _memoryMeta[board.id];
    if (meta == null) return false;
    try {
      final decoded = jsonDecode(meta);
      if (decoded is Map) {
        return decoded['fingerprint'] ==
            fingerprint(board, themeKey: themeKey);
      }
    } catch (_) {
      return false;
    }
    return false;
  }

  Uint8List? loadPng(BoardDocument board, {String themeKey = ''}) {
    if (!isFresh(board, themeKey: themeKey)) return null;
    return _memoryPng[board.id];
  }

  void save(BoardDocument board, Uint8List bytes, {String themeKey = ''}) {
    final path = _pngPath(board.id);
    final metaPath = _metaPath(board.id);
    final meta = jsonEncode({
      'fingerprint': fingerprint(board, themeKey: themeKey),
    });
    _memoryPng[board.id] = bytes;
    _memoryMeta[board.id] = meta;
    unawaited(
      Future.wait([
        FileStorageAdapter.instance.writeBytes(path, bytes),
        FileStorageAdapter.instance.writeString(metaPath, meta),
      ]),
    );
  }
}

/// Best-effort web stand-in for the VM [File] return type.
class WebCacheFile {
  WebCacheFile(this.path);

  final String path;

  bool existsSync() => false;

  Uint8List readAsBytesSync() => Uint8List(0);

  void writeAsBytesSync(List<int> bytes) {}

  String readAsStringSync() => '';

  void writeAsStringSync(String contents) {}
}
