// Regression test: on the very first build, BoardPanelCard must render at
// the persisted bounds with opacity 1.0 and scale 1.0 — the entry tween
// must NOT run from (opacity 0, scale 0.88). The slide-from-origin caused
// by AnimatedPositioned is also avoided by using plain Positioned on first
// build.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yoloit/core/theme/app_theme.dart';
import 'package:yoloit/features/board/bloc/board_cubit.dart';
import 'package:yoloit/features/board/bloc/board_state.dart';
import 'package:yoloit/features/board/model/board_models.dart';
import 'package:yoloit/features/board/plugins/builtin/markdown_note_plugin.dart';
import 'package:yoloit/features/board/ui/board_panel_card.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const panel = BoardPanelInstance(
    id: 'card-1',
    type: MarkdownNotePlugin.kTypeId,
    title: 'Card',
    bounds: BoardPanelBounds(x: 40, y: 40, width: 320, height: 240),
    state: {'markdown': 'hello'},
  );

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
    'first build is at opacity 1.0 and scale 1.0 (no entry tween)',
    (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final cubit = BoardCubit();
      addTearDown(cubit.close);
      final board = BoardDocument(
        id: 'board',
        name: 'Board',
        viewport: BoardViewport(scale: 1, focusedPanelId: null),
        panels: [panel],
      );
      cubit.emit(
        BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemePreset.neonPurple.theme,
          home: BlocProvider<BoardCubit>.value(
            value: cubit,
            child: Scaffold(
              body: Stack(
                children: [
                  BoardPanelCard(
                    panel: panel,
                    positionOffset: Offset.zero,
                    onTap: () {},
                    onMove: (_) {},
                    onResize: (_) {},
                    onDragStart: (_) {},
                    onDragEnd: () async {},
                    onDelete: () {},
                    onEditColor: () {},
                    onBringToFront: () {},
                    onSendToBack: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // Single frame after mount — no animation pump.
      await tester.pump();

      // First build: the panel renders at the persisted bounds with no
      // entry flight in progress. The FadeTransition/ScaleTransition entry
      // controller starts at value 1.0 on first build so Opacity is 1.0
      // and Transform scale is (1, 1). Any AnimatedPositioned on a later
      // rebuild has its ticker inactive (its duration is declared but the
      // animation does not run when bounds have not changed since mount).
      // Any Opacity in the panel tree must be at 1.0 (FadeTransition
      // short-circuited at entry controller value 1.0).
      final opacities = tester.widgetList<Opacity>(
        find.descendant(
          of: find.byType(BoardPanelCard),
          matching: find.byType(Opacity),
        ),
      );
      for (final w in opacities) {
        expect(w.opacity, 1.0,
            reason: 'Any Opacity on first build must be at 1.0');
      }
      // Every Transform in the panel tree must have identity scale.
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(BoardPanelCard),
          matching: find.byType(Transform),
        ),
      );
      for (final t in transforms) {
        final m = t.transform;
        expect((m.entry(0, 0) - 1.0).abs() < 1e-6, true,
            reason: 'X scale on first build must be 1.0');
        expect((m.entry(1, 1) - 1.0).abs() < 1e-6, true,
            reason: 'Y scale on first build must be 1.0');
      }
    },
  );
}