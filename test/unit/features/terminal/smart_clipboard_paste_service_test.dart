import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';

import 'fake_clipboard_reader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PlatformDirs.setInstance(const MacosPlatformDirs(homeOverride: '/tmp'));
  });

  tearDownAll(() {
    PlatformDirs.setInstance(const MacosPlatformDirs());
  });

  group('SmartClipboardPasteService.resolveText', () {
    test('pastes short terminal/log dump inline when allowed', () async {
      final text = 'Launching lib/main.dart on Chrome...\nflutter: [debug] done';
      final result = await SmartClipboardPasteService.instance.resolveText(
        text,
        allowInlineText: true,
      );
      expect(result, text);
    });

    test('saves long terminal/log dump to a temp file instead of truncating', () async {
      final logPrefix = 'Launching lib/main.dart on Chrome...\nflutter: [debug] ';
      final text = logPrefix + 'x' * 5000;
      final result = await SmartClipboardPasteService.instance.resolveText(
        text,
        allowInlineText: true,
      );

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));

      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), text);
    });

    test('saves terminal/log dump to a temp file when inline is not allowed', () async {
      final text = 'Launching lib/main.dart on Chrome...\nflutter: [debug] ' + 'x' * 1000;
      final result = await SmartClipboardPasteService.instance.resolveText(
        text,
        allowInlineText: false,
      );

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));

      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });

      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), text);
    });

    test('returns null for empty text', () async {
      final result = await SmartClipboardPasteService.instance.resolveText('');
      expect(result, isNull);
    });

    test('returns null for whitespace-only text', () async {
      final result = await SmartClipboardPasteService.instance.resolveText('   \n\n  ');
      expect(result, isNull);
    });
  });

  group('SmartClipboardPasteService.readInlineTextOrSavedFilePath', () {
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

    test('returns null when the clipboard is empty', () async {
      mockClipboardText(null);
      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, isNull);
    });

    test('returns short safe text inline when allowed', () async {
      mockClipboardText('hello world');
      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, 'hello world');
    });

    test('saves short text to a temp file when inline is not allowed',
        () async {
      mockClipboardText('hello world');
      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath();

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));

      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.readAsString(), 'hello world');
    });

    test('returns an existing file path as-is instead of wrapping it',
        () async {
      final tempFile = File(
        '${Directory.systemTemp.path}/yoloit_smart_paste_test.txt',
      );
      await tempFile.writeAsString('content');
      addTearDown(() async {
        if (await tempFile.exists()) await tempFile.delete();
      });

      mockClipboardText(tempFile.path);
      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, tempFile.path);
    });

    test('saves long terminal dump to a temp file', () async {
      mockClipboardText(
        'Launching lib/main.dart on Chrome...\nflutter: [debug] ${'x' * 3000}',
      );
      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));

      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.exists(), isTrue);
    });

    test('returns null when the clipboard channel throws', () async {
      messenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        throw PlatformException(code: 'unavailable');
      });

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, isNull);
    });
  });

  group('SmartClipboardPasteService.readInlineTextOrSavedFilePath super_clipboard',
      () {
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
      SmartClipboardPasteService.clipboardReaderOverride = null;
      messenger.setMockMethodCallHandler(SystemChannels.platform, null);
    });

    test('image clipboard content is saved through the file fallback',
        () async {
      SmartClipboardPasteService.clipboardReaderOverride =
          () async => ClipboardReader([
                FakeClipboardDataReader(
                  files: {Formats.png: Uint8List.fromList([1, 2, 3])},
                ),
              ]);
      // saveClipboardToFile re-reads the clipboard; with super_clipboard
      // unavailable in tests it lands on the Flutter clipboard fallback.
      mockClipboardText('image fallback text');

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));
      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
      expect(await file.readAsString(), 'image fallback text');
    });

    test('jpeg-only clipboard also takes the image branch', () async {
      SmartClipboardPasteService.clipboardReaderOverride =
          () async => ClipboardReader([
                FakeClipboardDataReader(
                  files: {Formats.jpeg: Uint8List.fromList([1, 2, 3])},
                ),
              ]);
      mockClipboardText('jpeg fallback');

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);

      expect(result, isNotNull);
      expect(result, endsWith('.txt'));
      final file = File(result!);
      addTearDown(() async {
        if (await file.exists()) await file.delete();
      });
    });

    test('plain text from super_clipboard is used for inline paste', () async {
      SmartClipboardPasteService.clipboardReaderOverride =
          () async => ClipboardReader([
                FakeClipboardDataReader(plainText: 'from super clipboard'),
              ]);
      mockClipboardText(null);

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, 'from super clipboard');
    });

    test('null reader falls back to the Flutter clipboard', () async {
      SmartClipboardPasteService.clipboardReaderOverride = () async => null;
      mockClipboardText('flutter clipboard text');

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, 'flutter clipboard text');
    });

    test('throwing reader falls back to the Flutter clipboard', () async {
      SmartClipboardPasteService.clipboardReaderOverride =
          () => Future.error(StateError('no clipboard'));
      mockClipboardText('rescued text');

      final result = await SmartClipboardPasteService.instance
          .readInlineTextOrSavedFilePath(allowInlineText: true);
      expect(result, 'rescued text');
    });
  });
}
