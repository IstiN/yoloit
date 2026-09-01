import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_icon.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_widgets.dart';

void main() {
  testWidgets('board overview card icon overlay golden', (tester) async {
    BoardDocument board(String id, String name, [BoardIconSpec? spec]) {
      return BoardDocument(
        id: id,
        name: name,
        metadata: {if (spec != null) 'icon': spec.toJson()},
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 320,
                  height: 220,
                  child: BoardOverviewCard(
                    board: board('emoji', 'Emoji Board', const BoardIconSpec(
                      kind: BoardIconSpec.kindEmoji,
                      value: '🚀',
                    )),
                    active: false,
                    previewPng: null,
                    onTap: () {},
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 320,
                  height: 220,
                  child: BoardOverviewCard(
                    board: board('fallback', 'Primark'),
                    active: true,
                    previewPng: null,
                    onTap: () {},
                  ),
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
      matchesGoldenFile('goldens/board_card_icon_overlay.png'),
    );
  });
}
