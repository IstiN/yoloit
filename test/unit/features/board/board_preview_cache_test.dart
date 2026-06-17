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

  test('fingerprint changes when revision or viewport changes', () {
    final base = board();
    final moved = board(translation: const Offset(12, 8));
    final revised = board(revision: 2);
    const themeKey = 'neonPurple:Brightness.dark:';

    expect(
      BoardPreviewCache.fingerprint(base, themeKey: themeKey),
      isNot(BoardPreviewCache.fingerprint(moved, themeKey: themeKey)),
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
    if (!tempDir.existsSync()) tempDir.createSync(recursive: true);
    cache.pngFile(doc.id).writeAsBytesSync(Uint8List.fromList([7]));

    expect(cache.isFresh(doc), isFalse);
    expect(cache.loadPng(doc), isNull);
  });
}
