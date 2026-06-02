import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/remote/yoloit_remote_client.dart';
import 'package:yoloit/core/remote/yoloitd_panel_catalog.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_preview.dart';

import '../helpers/remote_widget_smoke_data.dart';

void main() {
  for (final descriptor in yoloitdPanelTypes) {
    final type = descriptor['type'] as String;
    testWidgets('board overview renders remote widget type $type', (
      tester,
    ) async {
      final boardJson = remoteWidgetSmokeBoardJson();
      boardJson['panels'] = [
        (boardJson['panels'] as List).cast<Map<String, Object?>>().firstWhere(
          (panel) => panel['type'] == type,
        ),
      ];
      final board = remoteBoardFromJson(
        boardJson,
        baseUrl: 'http://127.0.0.1:43110',
        token: 'secret',
      );

      await _pumpPreview(tester, board);

      expect(tester.takeException(), isNull, reason: type);
    });
  }

  testWidgets('board overview renders every remote widget type', (
    tester,
  ) async {
    final board = remoteBoardFromJson(
      remoteWidgetSmokeBoardJson(),
      baseUrl: 'http://127.0.0.1:43110',
      token: 'secret',
    );

    await _pumpPreview(tester, board);

    expect(tester.takeException(), isNull);
    expect(board.panels, hasLength(yoloitdPanelTypes.length));
    expect(
      board.panels.map((panel) => panel.type),
      containsAll(yoloitdPanelTypes.map((entry) => entry['type'] as String)),
    );
  });
}

Future<void> _pumpPreview(WidgetTester tester, BoardDocument board) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppThemePreset.neonPurple.theme,
      home: Scaffold(
        body: SizedBox(
          width: 1200,
          height: 800,
          child: BoardOverviewPreview(board: board),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 700));
}
