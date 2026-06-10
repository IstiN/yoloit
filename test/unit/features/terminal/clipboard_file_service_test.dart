import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';

void main() {
  setUpAll(() {
    PlatformDirs.setInstance(const MacosPlatformDirs(homeOverride: '/tmp'));
  });

  tearDownAll(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  group('ClipboardFileService.tryResolveTextAsFilePath', () {
    test('returns the path when text points to an existing file', () async {
      final tempFile = File('${Directory.systemTemp.path}/yoloit_test_exist.txt');
      await tempFile.writeAsString('hello');
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath(tempFile.path);
      expect(result, tempFile.path);
    });

    test('returns null when text points to a non-existing file', () async {
      final fakePath = '${Directory.systemTemp.path}/yoloit_test_nonexistent_${DateTime.now().millisecondsSinceEpoch}.txt';
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath(fakePath);
      expect(result, isNull);
    });

    test('returns null for multi-line text', () async {
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath('/tmp/file.png\nsecond line');
      expect(result, isNull);
    });

    test('returns null for plain text that is not a path', () async {
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath('Hello world');
      expect(result, isNull);
    });

    test('trims whitespace before checking', () async {
      final tempFile = File('${Directory.systemTemp.path}/yoloit_test_trim.txt');
      await tempFile.writeAsString('hello');
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath('  ${tempFile.path}  ');
      expect(result, tempFile.path);
    });

    test('returns null for empty string', () async {
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath('');
      expect(result, isNull);
    });

    test('returns null for whitespace-only string', () async {
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath('   ');
      expect(result, isNull);
    });
  });

  group('ClipboardFileService.saveTextToFile', () {
    test('saves text to a temp file and returns its path', () async {
      final path = await ClipboardFileService.instance.saveTextToFile('sample content');
      addTearDown(() async {
        final file = File(path);
        if (await file.exists()) await file.delete();
      });

      expect(path, isNotEmpty);
      expect(path, endsWith('.txt'));

      final file = File(path);
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'sample content');
    });
  });
}
