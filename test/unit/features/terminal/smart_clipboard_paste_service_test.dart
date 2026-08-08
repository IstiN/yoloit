import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';

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
}
