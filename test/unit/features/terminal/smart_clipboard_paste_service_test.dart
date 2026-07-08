import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/platform/platform_dirs.dart';
import 'package:yoloit/features/terminal/data/smart_clipboard_paste_service.dart';

void main() {
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
}
