import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:yoloit/features/board/ui/board_file_picker.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('board_file_picker_native_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('_nativeInitialDirectory', () {
    test('returns null for null input', () {
      expect(
        BoardFilePicker.nativeInitialDirectoryForTest(null),
        isNull,
      );
    });

    test('returns null for empty or whitespace-only string', () {
      expect(
        BoardFilePicker.nativeInitialDirectoryForTest(''),
        isNull,
      );
      expect(
        BoardFilePicker.nativeInitialDirectoryForTest('   '),
        isNull,
      );
    });

    test('returns the expanded path when it points to an existing directory',
        () {
      final result =
          BoardFilePicker.nativeInitialDirectoryForTest(tempDir.path);
      expect(result, tempDir.path);
    });

    test('returns the parent directory when path points to an existing file',
        () {
      final file = File(p.join(tempDir.path, 'placeholder.txt'))
        ..createSync();
      final result = BoardFilePicker.nativeInitialDirectoryForTest(file.path);
      expect(result, tempDir.path);
    });

    test('returns null when path does not exist', () {
      final missing = p.join(tempDir.path, 'does_not_exist_dir');
      expect(
        BoardFilePicker.nativeInitialDirectoryForTest(missing),
        isNull,
      );
    });
  });

  group('_expandLocalPathForNative', () {
    test('returns HOME resolved when input is tilde', () {
      final home = Platform.environment['HOME'];
      expect(home, isNotNull);
      final result = BoardFilePicker.expandLocalPathForNativeForTest('~');
      expect(result, home);
    });

    test('returns HOME/sub resolved when HOME is set and input is ~/sub', () {
      final home = Platform.environment['HOME'];
      expect(home, isNotNull);
      final result =
          BoardFilePicker.expandLocalPathForNativeForTest('~/sub');
      expect(result, p.join(home!, 'sub'));
    });

    test('returns a plain path unchanged', () {
      const plain = '/var/log/app';
      final result =
          BoardFilePicker.expandLocalPathForNativeForTest(plain);
      expect(result, plain);
    });
  });
}
