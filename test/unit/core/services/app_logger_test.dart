import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/core/services/app_logger.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory home;

  setUp(() {
    home = Directory.systemTemp.createTempSync('app_logger_test_');
    PlatformDirs.setInstance(MacosPlatformDirs(homeOverride: home.path));
    SharedPreferences.setMockInitialValues({});
    // Silence the console: AppLogger chains whatever debugPrint is installed
    // when it hooks, and the rotation test writes >1 MB of log lines.
    debugPrint = (String? message, {int? wrapWidth}) {};
  });

  tearDown(() async {
    // Restore debugPrint / FlutterError hooks and drop buffered state.
    await AppLogger.instance.setEnabled(false);
    await AppLogger.instance.clearLog();
    debugPrint = debugPrintThrottled;
    PlatformDirs.setInstance(const MacosPlatformDirs());
    if (home.existsSync()) home.deleteSync(recursive: true);
  });

  String logFilePath() => p.join(PlatformDirs.instance.logsDir, 'app.log');

  group('AppLogger._flushBuffer', () {
    test('flushes buffered debug output to the log file', () async {
      await AppLogger.instance.init();
      AppLogger.instance.install();

      debugPrint('app_logger_test_marker_1');

      final log = await AppLogger.instance.readLog();
      expect(log, contains('app_logger_test_marker_1'));
      expect(File(logFilePath()).existsSync(), isTrue);
    });

    test('readLog on empty log returns placeholder', () async {
      await AppLogger.instance.init();
      final log = await AppLogger.instance.readLog();
      expect(log, '(no log file)');
    });

    test('clearLog removes the log file', () async {
      await AppLogger.instance.init();
      AppLogger.instance.install();
      debugPrint('app_logger_test_marker_2');
      await AppLogger.instance.readLog();
      expect(File(logFilePath()).existsSync(), isTrue);

      await AppLogger.instance.clearLog();
      expect(File(logFilePath()).existsSync(), isFalse);
    });

    test('swallows storage errors when the log path is not writable',
        () async {
      await AppLogger.instance.init();
      AppLogger.instance.install();

      // Make `logsDir` collide with an existing file so directory creation
      // and the append both fail — the flush must not throw.
      final logsPath = PlatformDirs.instance.logsDir;
      Directory(logsPath).parent.createSync(recursive: true);
      File(logsPath).createSync();

      debugPrint('app_logger_test_marker_3');
      final log = await AppLogger.instance.readLog();
      expect(log, '(no log file)');
    });
  });

  group('AppLogger._rotateIfNeeded', () {
    test('keeps the log intact while it stays below the size cap', () async {
      await AppLogger.instance.init();
      AppLogger.instance.install();

      debugPrint('small-entry');
      await AppLogger.instance.readLog();

      final length = File(logFilePath()).lengthSync();
      expect(length, greaterThan(0));
      expect(length, lessThan(5 * 1024 * 1024));
    });

    test('rotates an oversized log down to the most recent half', () async {
      Directory(PlatformDirs.instance.logsDir).createSync(recursive: true);
      // Pre-seed a log that already exceeds the 5 MB cap.
      final oversized = 'x' * (5 * 1024 * 1024 + 1024);
      File(logFilePath()).writeAsStringSync(oversized);

      await AppLogger.instance.init();
      AppLogger.instance.install();

      // Append more than 1 MB so the next flush triggers a rotation check.
      final chunk = 'y' * (100 * 1024);
      for (var i = 0; i < 12; i++) {
        debugPrint('$chunk$i');
      }
      debugPrint('app_logger_rotation_tail_marker');
      await AppLogger.instance.readLog();

      final rotated = File(logFilePath()).readAsStringSync();
      // 2.5 MB kept + ~1.2 MB appended must be well below the seeded 5 MB.
      expect(rotated.length, lessThan(oversized.length));
      expect(rotated, contains('app_logger_rotation_tail_marker'));
    }, timeout: const Timeout(Duration(seconds: 120)));
  });
}
