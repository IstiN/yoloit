import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_preview_cache.dart';

void main() {
  late Directory tempDir;
  late BoardPreviewCache cache;

  BoardDocument board({
    int revision = 1,
    double scale = 1.0,
    Offset translation = Offset.zero,
    String id = 'board-1',
  }) {
    return BoardDocument(
      id: id,
      name: 'Board',
      viewport: BoardViewport(scale: scale, translation: translation),
      metadata: {'historyRevision': revision},
    );
  }

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('yoloit_preview_cache_test_');
    cache = BoardPreviewCache(rootDir: tempDir);
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  test('fingerprint changes when revision or theme changes', () {
    final base = board();
    final moved = board(translation: const Offset(12, 8));
    final revised = board(revision: 2);
    const themeKey = 'neonPurple:Brightness.dark:';

    expect(
      BoardPreviewCache.fingerprint(base, themeKey: themeKey),
      BoardPreviewCache.fingerprint(moved, themeKey: themeKey),
      reason: 'overview thumbnails fit all panels, not viewport',
    );
    expect(
      BoardPreviewCache.fingerprint(base, themeKey: themeKey),
      isNot(BoardPreviewCache.fingerprint(revised, themeKey: themeKey)),
    );
    expect(
      BoardPreviewCache.fingerprint(base, themeKey: themeKey),
      isNot(
        BoardPreviewCache.fingerprint(base, themeKey: 'other-theme'),
      ),
    );
  });

  test('isFresh is false until png and meta are saved', () {
    final doc = board();
    const themeKey = 'dark';

    expect(cache.isFresh(doc, themeKey: themeKey), isFalse);

    cache.save(doc, Uint8List.fromList([1, 2, 3]), themeKey: themeKey);

    expect(cache.isFresh(doc, themeKey: themeKey), isTrue);
    expect(cache.loadPng(doc, themeKey: themeKey), Uint8List.fromList([1, 2, 3]));
  });

  test('stale revision invalidates cached preview', () {
    final original = board(revision: 3);
    const themeKey = 'dark';

    cache.save(original, Uint8List.fromList([9]), themeKey: themeKey);
    expect(cache.isFresh(original, themeKey: themeKey), isTrue);

    final updated = board(revision: 4);
    expect(cache.isFresh(updated, themeKey: themeKey), isFalse);
    expect(cache.loadPng(updated, themeKey: themeKey), isNull);
    expect(cache.pngFile(original.id).existsSync(), isTrue);
  });

  test('png without meta sidecar is treated as stale', () {
    final doc = board();
    final previewDir = Directory('${tempDir.path}/board_previews');
    if (!previewDir.existsSync()) {
      previewDir.createSync(recursive: true);
    }
    cache.pngFile(doc.id).writeAsBytesSync(Uint8List.fromList([7]));

    expect(cache.isFresh(doc), isFalse);
    expect(cache.loadPng(doc), isNull);
  });

  test('deleteForBoard removes png and sidecar for a deleted board', () {
    final doc = board();
    const themeKey = 'dark';

    cache.save(doc, Uint8List.fromList([1, 2, 3]), themeKey: themeKey);
    expect(cache.pngFile(doc.id).existsSync(), isTrue);
    expect(cache.metaFile(doc.id).existsSync(), isTrue);

    cache.deleteForBoard(doc.id);

    expect(cache.pngFile(doc.id).existsSync(), isFalse);
    expect(cache.metaFile(doc.id).existsSync(), isFalse);
    expect(cache.cachedBoardIds(), isEmpty);
  });

  test('deleteForBoard is a safe no-op for unknown board ids', () {
    expect(() => cache.deleteForBoard('never-cached'), returnsNormally);
    expect(cache.cachedBoardIds(), isEmpty);
  });

  test('sweepOrphans removes orphan files and keeps valid ones', () {
    final kept = board(id: 'board-kept');
    final orphan = board(id: 'board-orphan');
    const themeKey = 'dark';

    cache.save(kept, Uint8List.fromList([1]), themeKey: themeKey);
    cache.save(orphan, Uint8List.fromList([2]), themeKey: themeKey);
    expect(cache.cachedBoardIds(), containsAll([kept.id, orphan.id]));

    cache.sweepOrphans({kept.id});

    expect(cache.pngFile(kept.id).existsSync(), isTrue);
    expect(cache.metaFile(kept.id).existsSync(), isTrue);
    expect(cache.pngFile(orphan.id).existsSync(), isFalse);
    expect(cache.metaFile(orphan.id).existsSync(), isFalse);
    expect(cache.cachedBoardIds(), [kept.id]);
  });

  test('sweepOrphans is a no-op when the preview dir cannot be enumerated', () {
    // Block directory enumeration by placing a regular file where the
    // preview directory is expected.
    File('${tempDir.path}/board_previews').writeAsBytesSync(const [0]);

    expect(() => cache.sweepOrphans({'board-1'}), returnsNormally);
    expect(cache.cachedBoardIds(), isEmpty);
  });
}
