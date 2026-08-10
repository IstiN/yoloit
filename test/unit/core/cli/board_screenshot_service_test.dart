import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';
import 'package:yoloit/core/platform/file_storage_adapter.dart';
import 'package:yoloit/core/platform/file_storage_adapter_vm.dart';

void main() {
  group('BoardScreenshotService._snapshotTimestamp', () {
    test('parses a valid snapshot filename', () {
      final result = BoardScreenshotService.snapshotTimestampForTest(
        'board_snapshots/board_snapshot_1700000000000.png',
      );
      expect(result, isNotNull);
      expect(result!.millisecondsSinceEpoch, 1700000000000);
    });

    test('parses using only the basename', () {
      final a = BoardScreenshotService.snapshotTimestampForTest(
        '/some/deep/path/board_snapshot_1234567890.png',
      );
      expect(a, isNotNull);
      expect(a!.millisecondsSinceEpoch, 1234567890);
    });

    test('returns null when the prefix is wrong', () {
      expect(
        BoardScreenshotService.snapshotTimestampForTest('snapshot_123.png'),
        isNull,
      );
    });

    test('returns null when the suffix is wrong', () {
      expect(
        BoardScreenshotService.snapshotTimestampForTest(
          'board_snapshot_123.jpg',
        ),
        isNull,
      );
    });

    test('returns null when the timestamp is not numeric', () {
      expect(
        BoardScreenshotService.snapshotTimestampForTest(
          'board_snapshot_abc.png',
        ),
        isNull,
      );
    });

    test('returns null for an unrelated filename', () {
      expect(
        BoardScreenshotService.snapshotTimestampForTest('random.txt'),
        isNull,
      );
    });
  });

  group('BoardScreenshotService._capture (no boundary)', () {
    setUp(() {
      // Register a GlobalKey that has no mounted context — findRenderObject
      // returns null, so _capture loops 5 times then returns null.
      BoardScreenshotService.instance
          .registerBoundaryKey(GlobalKey());
    });

    test('capturePng returns null without a mounted RepaintBoundary', () async {
      expect(await BoardScreenshotService.instance.capturePng(), isNull);
    });

    test('captureBase64 returns null without a mounted boundary', () async {
      expect(await BoardScreenshotService.instance.captureBase64(), isNull);
    });

    test('captureJpegFile returns null without a mounted boundary', () async {
      expect(await BoardScreenshotService.instance.captureJpegFile(), isNull);
    });
  });

  group('BoardScreenshotService.cleanupOldSnapshotsForTest', () {
    late Directory tempDir;
    late FileStorageAdapter originalAdapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snapshots_cleanup_');
      originalAdapter = FileStorageAdapter.instance;
      // Point the adapter at the temp directory by using the default VM
      // adapter; the cleanup method operates on relative paths so we change
      // CWD to the temp dir.
      FileStorageAdapter.setInstanceForTest(const VmFileStorageAdapter());
      final origCwd = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = origCwd);
    });

    tearDown(() async {
      FileStorageAdapter.setInstanceForTest(originalAdapter);
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes files older than 1 hour and keeps newer ones', () async {
      final snapDir = Directory('${tempDir.path}/snaps')..createSync();
      final oldTs = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      final newTs = DateTime.now().millisecondsSinceEpoch;

      final oldFile = File('${snapDir.path}/board_snapshot_$oldTs.png')
        ..writeAsStringSync('old');
      final newFile = File('${snapDir.path}/board_snapshot_$newTs.png')
        ..writeAsStringSync('new');

      expect(oldFile.existsSync(), isTrue);
      expect(newFile.existsSync(), isTrue);

      await BoardScreenshotService.instance
          .cleanupOldSnapshotsForTest(snapDir.path);

      expect(oldFile.existsSync(), isFalse,
          reason: 'old snapshot should be deleted');
      expect(newFile.existsSync(), isTrue,
          reason: 'recent snapshot should be kept');
    });

    test('skips files with non-matching names', () async {
      final snapDir = Directory('${tempDir.path}/snaps2')..createSync();
      final junk = File('${snapDir.path}/random.txt')
        ..writeAsStringSync('junk');

      await BoardScreenshotService.instance
          .cleanupOldSnapshotsForTest(snapDir.path);

      // Non-matching files are left alone.
      expect(junk.existsSync(), isTrue);
    });

    test('handles empty directory gracefully', () async {
      final snapDir = Directory('${tempDir.path}/empty')..createSync();

      // Should complete without throwing.
      await BoardScreenshotService.instance
          .cleanupOldSnapshotsForTest(snapDir.path);
    });

    test('skips files with invalid timestamp in name', () async {
      final snapDir = Directory('${tempDir.path}/snaps3')..createSync();
      final badName =
          File('${snapDir.path}/board_snapshot_abc.png')
        ..writeAsStringSync('bad');

      await BoardScreenshotService.instance
          .cleanupOldSnapshotsForTest(snapDir.path);

      // _snapshotTimestamp returns null → file is not deleted.
      expect(badName.existsSync(), isTrue);
    });
  });

  // Tests the REAL cleanupOldSnapshots() method (line 137), which hardcodes
  // 'board_snapshots' as the directory path. We create that dir relative to
  // the temp CWD so the VmFileStorageAdapter.list() finds it.
  group('BoardScreenshotService.cleanupOldSnapshots (real method)', () {
    late Directory tempDir;
    late FileStorageAdapter originalAdapter;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('snapshots_real_');
      originalAdapter = FileStorageAdapter.instance;
      FileStorageAdapter.setInstanceForTest(const VmFileStorageAdapter());
      final origCwd = Directory.current;
      Directory.current = tempDir;
      addTearDown(() => Directory.current = origCwd);
    });

    tearDown(() async {
      FileStorageAdapter.setInstanceForTest(originalAdapter);
      if (tempDir.existsSync()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('deletes old snapshots from the default board_snapshots directory',
        () async {
      // The real method hardcodes 'board_snapshots' as a relative path.
      // With CWD at tempDir, this creates tempDir/board_snapshots/.
      final snapDir = Directory('${tempDir.path}/board_snapshots')
        ..createSync(recursive: true);

      final oldTs = DateTime.now()
          .subtract(const Duration(hours: 2))
          .millisecondsSinceEpoch;
      final newTs = DateTime.now().millisecondsSinceEpoch;

      final oldFile = File('${snapDir.path}/board_snapshot_$oldTs.png')
        ..writeAsStringSync('old');
      final newFile = File('${snapDir.path}/board_snapshot_$newTs.png')
        ..writeAsStringSync('new');

      await BoardScreenshotService.instance.cleanupOldSnapshots();

      expect(oldFile.existsSync(), isFalse,
          reason: 'old snapshot should be deleted by real cleanupOldSnapshots');
      expect(newFile.existsSync(), isTrue,
          reason: 'recent snapshot should survive');
    });

    test('completes without error when board_snapshots does not exist',
        () async {
      // No board_snapshots dir → list returns empty → no-op.
      await BoardScreenshotService.instance.cleanupOldSnapshots();
    });

    test('catch block swallows errors from adapter failures', () async {
      // Create the dir with an old file, but swap the adapter to one that
      // throws on list(). The try/catch in cleanupOldSnapshots must swallow.
      final snapDir = Directory('${tempDir.path}/board_snapshots')
        ..createSync(recursive: true);
      final oldTs = DateTime.now()
          .subtract(const Duration(hours: 3))
          .millisecondsSinceEpoch;
      File('${snapDir.path}/board_snapshot_$oldTs.png')
        ..writeAsStringSync('old');

      FileStorageAdapter.setInstanceForTest(_ThrowingAdapter());

      // Must not throw.
      await BoardScreenshotService.instance.cleanupOldSnapshots();
    });
  });

  group('BoardScreenshotService.captureJpegFile / saveSnapshotBytes', () {
    test('saveSnapshotBytes returns null for null input', () async {
      expect(
        await BoardScreenshotService.instance.saveSnapshotBytes(null),
        isNull,
      );
    });

    test('saveSnapshotBytes writes a file for valid PNG bytes', () async {
      // Generate a real 1x1 PNG via dart:ui to ensure the codec can decode it.
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 1, 1),
        ui.Paint()..color = const ui.Color(0xFFFF0000),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(1, 1);
      final byteData =
          await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      final pngBytes = byteData!.buffer.asUint8List();

      final result = await BoardScreenshotService.instance
          .saveSnapshotBytes(pngBytes);
      expect(result, isNotNull);
      expect(result, startsWith('board_snapshots/'));
      expect(result, endsWith('.png'));
    });

    test('saveSnapshotBytes catches errors for invalid bytes', () async {
      // Invalid bytes that can't be decoded as an image.
      final badBytes = Uint8List.fromList([0, 1, 2, 3]);
      final result = await BoardScreenshotService.instance
          .saveSnapshotBytes(badBytes);
      expect(result, isNull);
    });
  });
}

/// FileStorageAdapter that throws on every operation — used to verify the
/// try/catch in the real cleanupOldSnapshots() swallows errors.
class _ThrowingAdapter implements FileStorageAdapter {
  const _ThrowingAdapter();

  @override
  Future<bool> exists(String path) async => throw FileSystemException('boom');

  @override
  Future<String?> readString(String path) async => throw FileSystemException('boom');

  @override
  Future<Uint8List?> readBytes(String path) async =>
      throw FileSystemException('boom');

  @override
  Future<void> writeString(String path, String contents) async =>
      throw FileSystemException('boom');

  @override
  Future<void> appendString(String path, String contents) async =>
      throw FileSystemException('boom');

  @override
  Future<int?> length(String path) async => throw FileSystemException('boom');

  @override
  Future<void> writeBytes(String path, Uint8List bytes) async =>
      throw FileSystemException('boom');

  @override
  Future<void> delete(String path) async => throw FileSystemException('boom');

  @override
  Future<List<String>> list(String directoryPath) async =>
      throw FileSystemException('boom');
}
