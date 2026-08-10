import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/board_overview_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const boardOne = BoardDocument(id: 'b1', name: 'Board One');
  const boardTwo = BoardDocument(id: 'b2', name: 'Board Two');

  Future<({
    BoardDocument? Function() selected,
    Uint8List? Function() selectedPng,
    bool Function() closed,
  })>
  pumpLayer(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    BoardDocument? selected;
    Uint8List? selectedPng;
    var closed = false;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BoardOverviewLayer(
            activeBoardId: 'b1',
            boards: const [boardOne, boardTwo],
            previewPngs: const {},
            onSelectedBoard: (board, png) {
              selected = board;
              selectedPng = png;
            },
            onCreateBoard: () {},
            onCreateBoardFromTemplate: () {},
            onDisconnectRemoteBoard: (_) {},
            onDeleteRemoteBoard: (_) {},
            onDisconnectRemoteUrl: (_) {},
            onClose: () => closed = true,
            debugLog: (_) {},
          ),
        ),
      ),
    );
    // Let the 340ms zoom-in animation finish so cards settle into place.
    await tester.pumpAndSettle();

    return (
      selected: () => selected,
      selectedPng: () => selectedPng,
      closed: () => closed,
    );
  }

  testWidgets('tapping another board selects it with its preview', (
    tester,
  ) async {
    final layer = await pumpLayer(tester);

    await tester.tap(find.text('Board Two'));
    await tester.pumpAndSettle();

    expect(layer.selected()?.id, 'b2');
    expect(layer.selectedPng(), isNull);
    expect(layer.closed(), isFalse);
  });

  testWidgets('tapping the active board closes the overview', (tester) async {
    final layer = await pumpLayer(tester);

    await tester.tap(find.text('Board One'));
    await tester.pumpAndSettle();

    expect(layer.closed(), isTrue);
    expect(layer.selected(), isNull);
  });
}
