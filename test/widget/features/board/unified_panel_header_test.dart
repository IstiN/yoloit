import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/unified_panel_header.dart';

/// Regression tests for the panel header action-row layout.
///
/// The actions (duplicate / color / overflow / close) must stay pinned to the
/// right edge of the header on wide panels, and collapse into a scrollable
/// row only when the panel is too narrow to fit them.
void main() {
  BoardPanelInstance buildPanel() {
    return const BoardPanelInstance(
      id: 'p1',
      type: 'board.note.markdown',
      title: 'Notes',
      bounds: BoardPanelBounds(x: 0, y: 0, width: 800, height: 400),
    );
  }

  Future<void> pumpHeader(WidgetTester tester, double width) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: UnifiedPanelHeader(
              panel: buildPanel(),
              isSelected: false,
              isFocused: false,
              onDuplicate: () {},
              onToggleLocked: () {},
              onEditColor: () {},
              onBringToFront: () {},
              onSendToBack: () {},
              onSettings: () {},
              onDelete: () {},
              onRename: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('wide header pins the close button to the right edge', (
    tester,
  ) async {
    await pumpHeader(tester, 1366);

    final headerRect = tester.getRect(find.byType(UnifiedPanelHeader));
    final closeRect = tester.getRect(find.byTooltip('Remove panel'));

    // Header has 10px horizontal padding; the close button must sit at the
    // right edge instead of leaving a wide empty gap (regression from
    // wrapping the actions in a loose Flexible).
    expect(closeRect.right, closeTo(headerRect.right - 10, 1.0));
    // Sanity: the button must be far from the title area, i.e. in the right
    // quarter of the header.
    expect(closeRect.center.dx, greaterThan(headerRect.width * 0.75));
  });

  testWidgets('narrow header keeps actions in a scrollable row', (
    tester,
  ) async {
    await pumpHeader(tester, 260);

    expect(find.byTooltip('Remove panel'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    // No overflow errors should have been thrown during layout.
    expect(tester.takeException(), isNull);
  });
}
