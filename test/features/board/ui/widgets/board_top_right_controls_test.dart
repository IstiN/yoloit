import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/ui/widgets/board_top_right_controls.dart';

void main() {
  Widget buildSubject({
    required bool showMinimap,
    required VoidCallback onToggleMinimap,
    required VoidCallback onFitBoard,
    required bool isGridMode,
    required VoidCallback onToggleGrid,
    VoidCallback? onResetGrid,
    VoidCallback? onGroupByType,
  }) {
    return MaterialApp(
      theme: AppTheme.buildTheme(const Color(0xFF7C3AED)),
      home: Scaffold(
        body: Stack(
          children: [
            BoardTopRightControls(
              showMinimap: showMinimap,
              onToggleMinimap: onToggleMinimap,
              onFitBoard: onFitBoard,
              isGridMode: isGridMode,
              onToggleGrid: onToggleGrid,
              onResetGrid: onResetGrid,
              onGroupByType: onGroupByType,
              panels: const <BoardPanelInstance>[],
              transformController: TransformationController(),
              viewportSize: const Size(800, 600),
              origin: Offset.zero,
              onPanTo: (_) {},
            ),
          ],
        ),
      ),
    );
  }

  testWidgets('renders grid toggle button', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: false,
        onToggleGrid: () {},
      ),
    );

    expect(find.byIcon(Icons.grid_view_outlined), findsOneWidget);
  });

  testWidgets('calls onToggleGrid when grid button is tapped', (tester) async {
    var toggled = false;
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: false,
        onToggleGrid: () => toggled = true,
      ),
    );

    await tester.tap(find.byIcon(Icons.grid_view_outlined));
    expect(toggled, isTrue);
  });

  testWidgets('shows filled grid icon when grid mode is enabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: true,
        onToggleGrid: () {},
      ),
    );

    expect(find.byIcon(Icons.grid_view), findsOneWidget);
    expect(find.byIcon(Icons.grid_view_outlined), findsNothing);
  });

  testWidgets('calls onResetGrid when grid button is long-pressed', (
    tester,
  ) async {
    var reset = false;
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: true,
        onToggleGrid: () {},
        onResetGrid: () => reset = true,
      ),
    );

    await tester.longPress(find.byIcon(Icons.grid_view));
    expect(reset, isTrue);
  });

  testWidgets('shows reset grid button only in grid mode', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: false,
        onToggleGrid: () {},
        onResetGrid: () {},
      ),
    );

    expect(find.byIcon(Icons.replay), findsNothing);

    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: true,
        onToggleGrid: () {},
        onResetGrid: () {},
      ),
    );

    expect(find.byIcon(Icons.replay), findsOneWidget);
  });

  testWidgets('shows group-by-type button only in grid mode', (tester) async {
    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: false,
        onToggleGrid: () {},
        onGroupByType: () {},
      ),
    );

    expect(find.byIcon(Icons.dashboard), findsNothing);

    await tester.pumpWidget(
      buildSubject(
        showMinimap: false,
        onToggleMinimap: () {},
        onFitBoard: () {},
        isGridMode: true,
        onToggleGrid: () {},
        onGroupByType: () {},
      ),
    );

    expect(find.byIcon(Icons.dashboard), findsOneWidget);
  });
}
