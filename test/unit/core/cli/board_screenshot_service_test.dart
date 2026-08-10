import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/cli/board_screenshot_service.dart';

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
}
