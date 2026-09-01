import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_icon.dart';

void main() {
  testWidgets('board icon gallery golden', (tester) async {
    final dir = Directory.systemTemp.createTempSync('board_icon_golden');
    addTearDown(() => dir.deleteSync(recursive: true));
    // Use a real project asset as the "file" icon (fake PNG bytes do not
    // decode reliably in tests).
    final pngFile = File('assets/icon/yoloit_foreground.png');
    expect(pngFile.existsSync(), isTrue);

    BoardIcon.debugResolverOverride = null;
    addTearDown(() => BoardIcon.debugResolverOverride = null);

    BoardDocument board(String id, String name, [BoardIconSpec? spec]) {
      return BoardDocument(
        id: id,
        name: name,
        metadata: {if (spec != null) 'icon': spec.toJson()},
      );
    }

    final icons = <Widget>[
      BoardIcon(
        board: board('emoji', 'Rocket', const BoardIconSpec(
          kind: BoardIconSpec.kindEmoji,
          value: '🚀',
        )),
        size: 32,
      ),
      BoardIcon(
        board: board('builtin', 'YoLoIT', const BoardIconSpec(
          kind: BoardIconSpec.kindBuiltin,
          value: 'yoloit',
        )),
        size: 32,
      ),
      BoardIcon(
        board: board('file', 'File', BoardIconSpec(
          kind: BoardIconSpec.kindFile,
          value: pngFile.path,
        )),
        size: 32,
      ),
      BoardIcon(board: board('fb1', 'Primark'), size: 32),
      BoardIcon(board: board('fb2', 'dmtools'), size: 32),
      BoardIcon(board: board('fb3', 'AI KB'), size: 32),
    ];

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          backgroundColor: const Color(0xFF1A1A2E),
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final icon in icons)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: icon,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/board_icon_gallery.png'),
    );
  });
}
