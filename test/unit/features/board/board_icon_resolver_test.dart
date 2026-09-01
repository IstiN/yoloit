import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/services/board_icon_resolver.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('board_icon_resolver_test');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  File createFile(String relative) {
    final file = File('${tempDir.path}${Platform.pathSeparator}$relative');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47]);
    return file;
  }

  group('BoardIconResolver.detectInFolder', () {
    test('returns null for empty or unknown folder', () {
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(''), isNull);
      expect(resolver.detectInFolder(tempDir.path), isNull);
    });

    test('detects Flutter macOS app icon', () {
      final icon = createFile(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      );
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), icon.path);
    });

    test('detects Flutter web icon', () {
      final icon = createFile('web/icons/Icon-192.png');
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), icon.path);
    });

    test('detects generic assets icon', () {
      final icon = createFile('assets/icon.png');
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), icon.path);
    });

    test('prefers app icon over generic assets icon', () {
      final appIcon = createFile(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      );
      createFile('assets/icon.png');
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), appIcon.path);
    });

    test('caches result and invalidate forces re-detection', () {
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), isNull);

      final icon = createFile('icon.png');
      // Cached miss — still null until invalidated.
      expect(resolver.detectInFolder(tempDir.path), isNull);

      resolver.invalidate(tempDir.path);
      expect(resolver.detectInFolder(tempDir.path), icon.path);

      icon.deleteSync();
      // Cached hit — still the old path until fully invalidated.
      expect(resolver.detectInFolder(tempDir.path), icon.path);
      resolver.invalidate();
      expect(resolver.detectInFolder(tempDir.path), isNull);
    });
  });

  group('BoardIconResolver scoring scan', () {
    test('finds app icon in branding directory', () {
      final icon = createFile('branding/yoclip_app_icon_dark_1024.png');
      createFile('branding/yoclip_logo_2400.png');
      final resolver = BoardIconResolver();
      // app_icon (400 + 102 - 50 variant) still beats logo (100 + 240).
      expect(resolver.detectInFolder(tempDir.path), icon.path);
    });

    test('prefers larger icon over smaller logo', () {
      createFile('icon/icon_512.png');
      createFile('images/logo.png');
      final resolver = BoardIconResolver();
      expect(
        resolver.detectInFolder(tempDir.path),
        endsWith('icon_512.png'),
      );
    });

    test('detects icon inside a nested flutter project directory', () {
      createFile('flutter_app/pubspec.yaml');
      final icon = createFile(
        'flutter_app/macos/Runner/Assets.xcassets/AppIcon.appiconset/'
        'app_icon_1024.png',
      );
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), icon.path);
    });

    test('skips build and hidden directories when nesting', () {
      createFile('build/pubspec.yaml');
      createFile('build/assets/icon.png');
      final resolver = BoardIconResolver();
      expect(resolver.detectInFolder(tempDir.path), isNull);
    });

    test('scores file names', () {
      expect(BoardIconResolver.scoreIconFileName('app_icon_1024.png'), 502);
      expect(BoardIconResolver.scoreIconFileName('icon_512.png'), 351);
      expect(BoardIconResolver.scoreIconFileName('favicon.png'), 200);
      expect(BoardIconResolver.scoreIconFileName('logo.svg'), 100);
      expect(BoardIconResolver.scoreIconFileName('readme.md'), 0);
      expect(BoardIconResolver.scoreIconFileName('random.png'), 0);
      expect(BoardIconResolver.scoreIconFileName('icon_dark_512.png'), 301);
    });
  });

  group('BoardIconResolver.findIconCandidates', () {
    test('returns empty list for empty folder', () {
      final resolver = BoardIconResolver();
      expect(resolver.findIconCandidates(''), isEmpty);
      expect(resolver.findIconCandidates(tempDir.path), isEmpty);
    });

    test('returns all candidates best first', () {
      final appIcon = createFile(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png',
      );
      final appIcon512 = createFile(
        'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png',
      );
      final scanned = createFile('branding/app_icon_dark_1024.png');
      createFile('branding/logo.svg');
      final resolver = BoardIconResolver();
      final candidates = resolver.findIconCandidates(tempDir.path);
      expect(candidates.length, 4);
      // Well-known locations first (in priority order), then scanned files.
      expect(candidates[0], appIcon.path);
      expect(candidates[1], appIcon512.path);
      expect(candidates[2], scanned.path);
      // Best candidate matches detectInFolder.
      expect(candidates.first, resolver.detectInFolder(tempDir.path));
    });

    test('includes nested project candidates and honors limit', () {
      createFile('flutter_app/pubspec.yaml');
      final nested = createFile('flutter_app/web/icons/Icon-512.png');
      final resolver = BoardIconResolver();
      expect(
        resolver.findIconCandidates(tempDir.path),
        contains(nested.path),
      );
      expect(
        resolver.findIconCandidates(tempDir.path, limit: 1),
        hasLength(1),
      );
    });
  });

  group('BoardIconResolver.resolveForBoard', () {
    test('explicit override wins over auto-detection', () {
      createFile('assets/icon.png');
      const board = BoardDocument(
        id: 'b',
        name: 'B',
        metadata: {
          'icon': {'kind': 'emoji', 'value': '🚀'},
        },
      );
      final resolver = BoardIconResolver();
      final spec = resolver.resolveForBoard(board);
      expect(spec?.kind, BoardIconSpec.kindEmoji);
      expect(spec?.value, '🚀');
    });

    test('auto-detects file icon from default folder', () {
      final icon = createFile('assets/icon.png');
      final board = BoardDocument(
        id: 'b',
        name: 'B',
        metadata: {'defaultFolder': tempDir.path},
      );
      final resolver = BoardIconResolver();
      final spec = resolver.resolveForBoard(board);
      expect(spec?.kind, BoardIconSpec.kindFile);
      expect(spec?.value, icon.path);
    });

    test('returns null when nothing is found', () {
      final board = BoardDocument(
        id: 'b',
        name: 'B',
        metadata: {'defaultFolder': tempDir.path},
      );
      final resolver = BoardIconResolver();
      expect(resolver.resolveForBoard(board), isNull);
    });
  });
}
