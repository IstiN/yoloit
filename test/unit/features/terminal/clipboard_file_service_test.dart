import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/data/clipboard_file_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test('returns the URL as-is for http and https links', () async {
      expect(
        await ClipboardFileService.instance.tryResolveTextAsFilePath('https://example.com'),
        'https://example.com',
      );
      expect(
        await ClipboardFileService.instance.tryResolveTextAsFilePath('http://localhost:8080'),
        'http://localhost:8080',
      );
    });

    test('returns the path when text points to an existing directory', () async {
      final tempDir = Directory('${Directory.systemTemp.path}/yoloit_test_dir_${DateTime.now().millisecondsSinceEpoch}');
      await tempDir.create();
      addTearDown(() async {
        if (await tempDir.exists()) await tempDir.delete();
      });

      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath(tempDir.path);
      expect(result, tempDir.path);
    });

    test('returns null when text points to a non-existing directory', () async {
      final fakePath = '${Directory.systemTemp.path}/yoloit_test_nonexistent_dir_${DateTime.now().millisecondsSinceEpoch}';
      final result = await ClipboardFileService.instance.tryResolveTextAsFilePath(fakePath);
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

    test('normalizes text by trimming trailing whitespace and blank runs', () async {
      final path = await ClipboardFileService.instance.saveTextToFile(
        '\n\n   \nhello   \n\n\n\nworld\n   \n\n',
      );
      addTearDown(() async {
        final file = File(path);
        if (await file.exists()) await file.delete();
      });

      final content = await File(path).readAsString();
      expect(content, 'hello\n\nworld');
    });

    test('strips ANSI escape sequences during normalization', () async {
      final path = await ClipboardFileService.instance.saveTextToFile(
        '\x1B[31merror\x1B[0m\n\x1B[1mbold\x1B[0m',
      );
      addTearDown(() async {
        final file = File(path);
        if (await file.exists()) await file.delete();
      });

      final content = await File(path).readAsString();
      expect(content, 'error\nbold');
    });
  });

  group('ClipboardFileService.isSafeInlineText', () {
    test('returns true for short single-line plain text', () {
      expect(
        ClipboardFileService.instance.isSafeInlineText(
          'chore/bump-agents-submodule-token-usage had recent pushes about 1 hour ago',
        ),
        isTrue,
      );
    });

    test('returns false for empty text', () {
      expect(ClipboardFileService.instance.isSafeInlineText(''), isFalse);
    });

    test('returns false for multi-line text', () {
      expect(
        ClipboardFileService.instance.isSafeInlineText('line one\nline two'),
        isFalse,
      );
    });

    test('returns false for text containing control characters', () {
      expect(
        ClipboardFileService.instance.isSafeInlineText('hello\x1b[31mworld'),
        isFalse,
      );
    });

    test('returns false when text exceeds maxLength', () {
      final longText = 'a' * 1001;
      expect(ClipboardFileService.instance.isSafeInlineText(longText), isFalse);
    });

    test('returns true for text exactly at maxLength', () {
      final text = 'a' * 1000;
      expect(ClipboardFileService.instance.isSafeInlineText(text), isTrue);
    });

    test('allows tab characters', () {
      expect(
        ClipboardFileService.instance.isSafeInlineText('col1\tcol2'),
        isTrue,
      );
    });

    test('respects custom maxLength', () {
      expect(
        ClipboardFileService.instance.isSafeInlineText('abcd', maxLength: 3),
        isFalse,
      );
      expect(
        ClipboardFileService.instance.isSafeInlineText('abc', maxLength: 3),
        isTrue,
      );
    });
  });

  group('ClipboardFileService.saveClipboardToFile', () {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    void mockClipboardText(String? text) {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.getData') {
          if (text == null) return null;
          return <String, dynamic>{'text': text};
        }
        return null;
      });
    }

    tearDown(() {
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('saves clipboard text to a temp .txt file', () async {
      mockClipboardText('hello from clipboard');

      final path = await ClipboardFileService.instance.saveClipboardToFile();
      expect(path, isNotNull);
      expect(path, endsWith('.txt'));

      final file = File(path!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), 'hello from clipboard');
    });

    test('normalizes clipboard text before saving', () async {
      mockClipboardText('\x1B[31merror\x1B[0m\n\n\nbold   \n\n');

      final path = await ClipboardFileService.instance.saveClipboardToFile();
      expect(path, isNotNull);

      final file = File(path!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      expect(await file.readAsString(), 'error\n\nbold');
    });

    test('returns null when the clipboard is empty', () async {
      mockClipboardText(null);
      final path = await ClipboardFileService.instance.saveClipboardToFile();
      expect(path, isNull);
    });

    test('returns null when the clipboard text is empty', () async {
      mockClipboardText('');
      final path = await ClipboardFileService.instance.saveClipboardToFile();
      expect(path, isNull);
    });

    test('returns null when the clipboard channel throws', () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        throw PlatformException(code: 'unavailable');
      });

      final path = await ClipboardFileService.instance.saveClipboardToFile();
      expect(path, isNull);
    });
  });
}
