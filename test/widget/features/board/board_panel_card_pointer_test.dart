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

  Future<BoardPanelCardState> pumpCard(
    WidgetTester tester, {
    required void Function() onTap,
    bool focused = false,
  }) async {
    tester.view.physicalSize = const Size(800, 600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cubit = BoardCubit();
    addTearDown(cubit.close);
    final board = BoardDocument(
      id: 'board',
      name: 'Board',
      viewport: BoardViewport(
        scale: 1,
        focusedPanelId: focused ? panel.id : null,
      ),
      panels: const [panel],
    );
    cubit.emit(
      BoardState(boards: [board], activeBoardId: 'board', isLoaded: true),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemePreset.neonPurple.theme,
        home: Scaffold(
          body: BlocProvider.value(
            value: cubit,
            child: Stack(
              children: [
                BoardPanelCard(
                  panel: panel,
                  positionOffset: Offset.zero,
                  onTap: onTap,
                  onMove: (_) {},
                  onResize: (_) {},
                  onDragStart: (_) {},
                  onDragEnd: () {},
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
    // Let the entry animation finish so hit testing hits the final layout.
    await tester.pump(const Duration(milliseconds: 500));
    final state = tester.state<BoardPanelCardState>(
      find.byType(BoardPanelCard),
    );
    return state;
  }

  group('panel pointer down via real pointer events', () {
    testWidgets('unfocused non-webpage panel does NOT auto-focus on pointer down', (
      tester,
    ) async {
      var taps = 0;
      await pumpCard(tester, onTap: () => taps++);

      final gesture = await tester.startGesture(const Offset(200, 220));
      await tester.pump();
      expect(taps, 0);
      await gesture.up();
      await tester.pump();
    });

    testWidgets('focused non-webpage panel ignores pointer down', (
      tester,
    ) async {
      var taps = 0;
      await pumpCard(tester, onTap: () => taps++, focused: true);

      final gesture = await tester.startGesture(const Offset(200, 220));
      await tester.pump();
      expect(taps, 0);
      await gesture.up();
      await tester.pump();
    });
  });

  group('panel pointer down branches', () {
    testWidgets('webpage panels focus when unfocused and release Flutter '
        'focus when already focused', (tester) async {
      var taps = 0;
      final cardState = await pumpCard(tester, onTap: () => taps++);

      // Webpage + not focused: taps through to focus the panel.
      cardState.debugHandlePanelPointerDown(
        isWebpage: true,
        isFocused: false,
      );
      expect(taps, 1);

      // Webpage + focused: no re-focus; Flutter focus is released instead so
      // the native web overlay can take over.
      cardState.debugHandlePanelPointerDown(
        isWebpage: true,
        isFocused: true,
      );
      expect(taps, 1);

      // Non-webpage + focused: no-op.
      cardState.debugHandlePanelPointerDown(
        isWebpage: false,
        isFocused: true,
      );
      expect(taps, 1);

      // Non-webpage + unfocused: does NOT auto-focus (removed to prevent
      // viewport jump / mouse offset when clicking panels to drag).
      cardState.debugHandlePanelPointerDown(
        isWebpage: false,
        isFocused: false,
      );
      expect(taps, 1);
    });
  });
}
