import 'dart:io';

import 'package:flutter/material.dart';
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
}
